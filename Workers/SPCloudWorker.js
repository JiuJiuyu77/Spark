/**
 * Workbench 远程构建 Worker（Cloudflare Workers）
 *
 * 作用：把「云端构建」这件麻烦事收成一个 HTTP 接口 —— 手机上的 Workbench
 * 把项目 zip 传上来，Worker 存进 R2，然后用 GitHub `workflow_dispatch`
 * 触发 Workbench 的 Actions 工作流；构建完成后手机轮询状态即可拿产物链接。
 *
 * 设计取舍：
 *   · 不在 Worker 里跑编译（Workers 没有 Xcode/clang，也没法跑 macOS）。
 *     Worker 只做「编排 + 存储 + 鉴权」，真正编译交给 GitHub 的 macos runner。
 *   · 不引入任何 npm 依赖，单个文件即可 `wrangler deploy`。
 *   · 所有响应都不缓存，错误信息统一 {ok:false, error, detail}。
 *
 * 需要的绑定 / 变量（都在 wrangler.toml 里配置）：
 *   KV   JOBS      构建任务状态
 *   R2   UPLOADS   项目 zip 与构建日志
 *   secret TOKEN   调用方的 Bearer Token（自己和 App 约定）
 *   secret GH_TOKEN  GitHub PAT（需要 actions:write 与 contents:read）
 *   var  GH_OWNER / GH_REPO / GH_WORKFLOW / GH_REF
 *   var  MAX_UPLOAD_MB（默认 32）
 */

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data, null, 2), { status, headers: JSON_HEADERS });

const fail = (error, detail = '', status = 400) => json({ ok: false, error, detail }, status);

/** 常量时间比较，避免 token 计时攻击 */
function safeEqual(a, b) {
  const x = String(a || '');
  const y = String(b || '');
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}

function newJobId() {
  const letters = '0123456789abcdef';
  let s = '';
  const buf = new Uint8Array(16);
  crypto.getRandomValues(buf);
  for (const b of buf) s += letters[b >> 4] + letters[b & 15];
  return `rb_${s}`;
}

function githubApi(env, path, init = {}) {
  const url = path.startsWith('http') ? path : `https://api.github.com${path}`;
  return fetch(url, {
    ...init,
    headers: {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${env.GH_TOKEN}`,
      'x-github-api-version': '2022-11-28',
      'user-agent': 'Workbench-Worker',
      ...(init.headers || {}),
    },
  });
}

/** 触发 workflow_dispatch，inputs 里塞项目元信息 */
async function dispatch(env, inputs) {
  const owner = env.GH_OWNER;
  const repo = env.GH_REPO;
  const workflow = env.GH_WORKFLOW || 'build.yml';
  const ref = env.GH_REF || 'main';
  if (!owner || !repo) throw new Error('GH_OWNER / GH_REPO 未配置');

  const res = await githubApi(env, `/repos/${owner}/${repo}/actions/workflows/${workflow}/dispatches`, {
    method: 'POST',
    body: JSON.stringify({ ref, inputs }),
  });
  if (res.status !== 204) {
    const text = await res.text();
    throw new Error(`workflow_dispatch 失败 ${res.status}: ${text.slice(0, 400)}`);
  }
  // 204 之后要等一会儿 runs 才会出现
  return { dispatched: true, workflow, ref };
}

/** 查最近一次由我们触发的 run（按 created 时间倒序，匹配 displayTitle） */
async function latestRun(env, jobId) {
  const owner = env.GH_OWNER;
  const repo = env.GH_REPO;
  const workflow = env.GH_WORKFLOW || 'build.yml';
  const res = await githubApi(env, `/repos/${owner}/${repo}/actions/workflows/${workflow}/runs?per_page=20`);
  if (!res.ok) return null;
  const data = await res.json();
  const runs = data.workflow_runs || [];
  return runs.find((r) => (r.display_title || '').includes(jobId)) || runs[0] || null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === '/' || path === '/health') {
      return json({
        ok: true,
        service: 'spark-worker',
        version: env.SP_VERSION || '1.0.0',
        ts: new Date().toISOString(),
        caps: ['upload', 'dispatch', 'status', 'artifact', 'log'],
      });
    }

    // ---- 鉴权 ----
    const auth = request.headers.get('authorization') || '';
    const bearer = auth.replace(/^Bearer\s+/i, '');
    if (!env.TOKEN || !safeEqual(bearer, env.TOKEN)) {
      return fail('unauthorized', '缺少或错误的 Bearer Token', 401);
    }

    try {
      if (path === '/upload' && request.method === 'PUT') return await handleUpload(request, env, url);
      if (path === '/dispatch' && request.method === 'POST') return await handleDispatch(request, env);
      if (path === '/status' && request.method === 'GET') return await handleStatus(env, url);
      if (path === '/artifact' && request.method === 'GET') return await handleArtifact(env, url);
      if (path === '/log' && request.method === 'GET') return await handleLog(env, url);
      if (path === '/jobs' && request.method === 'GET') return await handleList(env);
      if (path.startsWith('/jobs/') && request.method === 'DELETE') return await handleCancel(env, path);
      return fail('not_found', path, 404);
    } catch (err) {
      return fail('internal', String(err && err.stack ? err.stack : err).slice(0, 800), 500);
    }
  },
};

/** PUT /upload?job=xxx  body=zip */
async function handleUpload(request, env, url) {
  const jobId = url.searchParams.get('job') || newJobId();
  const maxMB = Number(env.MAX_UPLOAD_MB || 32);
  const body = request.body;
  if (!body) return fail('empty_body');

  const length = Number(request.headers.get('content-length') || 0);
  if (length && length > maxMB * 1024 * 1024) return fail('too_large', `> ${maxMB}MB`, 413);

  const key = `projects/${jobId}.zip`;
  await env.UPLOADS.put(key, body, {
    httpMetadata: { contentType: 'application/zip' },
    customMetadata: { jobId, uploadedAt: new Date().toISOString() },
  });
  await env.JOBS.put(`job:${jobId}`, JSON.stringify({
    id: jobId,
    state: 'uploaded',
    createdAt: new Date().toISOString(),
    uploadKey: key,
    size: length || null,
  }), { expirationTtl: 60 * 60 * 24 * 7 });
  return json({ ok: true, job: jobId, key, size: length || null });
}

/** POST /dispatch  {job, options, project} */
async function handleDispatch(request, env) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return fail('bad_json');
  }
  const jobId = payload.job || newJobId();
  const record = {
    id: jobId,
    state: 'dispatching',
    createdAt: new Date().toISOString(),
    options: payload.options || {},
    project: payload.project || {},
    runId: null,
    runUrl: null,
    conclusion: null,
  };

  const result = await dispatch(env, {
    job_id: jobId,
    // workflow 里会以此作为 display_title，方便回查
    note: `Workbench ${payload.project?.name || ''}`.trim().slice(0, 60),
    options_json: JSON.stringify(payload.options || {}).slice(0, 3000),
  });

  record.state = 'dispatched';
  record.runUrl = null;
  record.workflow = result.workflow;
  await env.JOBS.put(`job:${jobId}`, JSON.stringify(record), { expirationTtl: 60 * 60 * 24 * 7 });
  return json({ ok: true, job: jobId, ...record });
}

/** GET /status?job=xxx */
async function handleStatus(env, url) {
  const jobId = url.searchParams.get('job');
  if (!jobId) return fail('missing_job');
  const raw = await env.JOBS.get(`job:${jobId}`);
  if (!raw) return fail('unknown_job', jobId, 404);

  const record = JSON.parse(raw);
  // 从 GitHub 侧同步一次真实状态
  const run = await latestRun(env, jobId);
  if (run) {
    record.runId = run.id;
    record.runUrl = run.html_url;
    record.runStatus = run.status;        // queued / in_progress / completed
    record.conclusion = run.conclusion;   // success / failure / cancelled ...
    record.state = run.status === 'completed'
      ? (run.conclusion === 'success' ? 'succeeded' : 'failed')
      : run.status;
    await env.JOBS.put(`job:${jobId}`, JSON.stringify(record), { expirationTtl: 60 * 60 * 24 * 7 });
  }
  return json({ ok: true, ...record });
}

/** GET /artifact?job=xxx&name=xxx.deb —— 302 到 GitHub 的短期下载地址 */
async function handleArtifact(env, url) {
  const jobId = url.searchParams.get('job');
  if (!jobId) return fail('missing_job');
  const raw = await env.JOBS.get(`job:${jobId}`);
  if (!raw) return fail('unknown_job', jobId, 404);
  const record = JSON.parse(raw);
  const run = await latestRun(env, jobId);
  if (!run) return fail('no_run', '', 404);

  const list = await githubApi(env, `/repos/${env.GH_OWNER}/${env.GH_REPO}/actions/runs/${run.id}/artifacts`);
  if (!list.ok) return fail('artifact_list_failed', await list.text(), 502);
  const data = await list.json();
  const artifacts = data.artifacts || [];
  const wanted = url.searchParams.get('name');
  const pick = wanted ? artifacts.find((a) => a.name === wanted) : artifacts[0];
  if (!pick) return fail('no_artifact', JSON.stringify(artifacts.map((a) => a.name)), 404);

  // 用 token 换一次性的匿名下载 URL（R2 / Worker 里不方便中转大文件）
  const zipRes = await githubApi(env, `/repos/${env.GH_OWNER}/${env.GH_REPO}/actions/artifacts/${pick.id}/zip`);
  if (zipRes.status >= 300 && zipRes.status < 400) {
    return new Response(null, { status: 302, headers: { location: zipRes.headers.get('location') || '' } });
  }
  return new Response(zipRes.body, {
    status: zipRes.status,
    headers: { 'content-type': 'application/zip', 'cache-control': 'no-store' },
  });
}

/** GET /log?job=xxx —— 从 GitHub 拉 job 日志（纯文本，截断到 2MB） */
async function handleLog(env, url) {
  const jobId = url.searchParams.get('job');
  if (!jobId) return fail('missing_job');
  const run = await latestRun(env, jobId);
  if (!run) return fail('no_run', '', 404);
  const jobsRes = await githubApi(env, `/repos/${env.GH_OWNER}/${env.GH_REPO}/actions/runs/${run.id}/jobs`);
  if (!jobsRes.ok) return fail('jobs_failed', await jobsRes.text(), 502);
  const { jobs = [] } = await jobsRes.json();
  if (!jobs.length) return json({ ok: true, log: '(还没有 job)' });
  const logs = [];
  for (const j of jobs) {
    const r = await githubApi(env, `/repos/${env.GH_OWNER}/${env.GH_REPO}/actions/jobs/${j.id}/logs`, {
      redirect: 'follow',
    });
    if (r.ok) {
      const text = await r.text();
      logs.push(`===== ${j.name} (${j.conclusion || j.status}) =====\n${text}`);
    } else {
      logs.push(`===== ${j.name}：日志获取失败 ${r.status} =====`);
    }
  }
  const text = logs.join('\n\n').slice(0, 2 * 1024 * 1024);
  await env.UPLOADS.put(`logs/${jobId}.txt`, text);
  return new Response(text, {
    headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' },
  });
}

/** GET /jobs —— 最近任务列表（Worker 自己记录的） */
async function handleList(env) {
  const list = await env.JOBS.list({ prefix: 'job:', limit: 100 });
  const jobs = [];
  for (const key of list.keys) {
    const raw = await env.JOBS.get(key.name);
    if (raw) jobs.push(JSON.parse(raw));
  }
  jobs.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  return json({ ok: true, count: jobs.length, jobs });
}

/** DELETE /jobs/<id> —— 取消 GitHub 上的 run 并删记录 */
async function handleCancel(env, path) {
  const jobId = path.slice('/jobs/'.length);
  const raw = await env.JOBS.get(`job:${jobId}`);
  if (!raw) return fail('unknown_job', jobId, 404);
  const run = await latestRun(env, jobId);
  if (run) {
    await githubApi(env, `/repos/${env.GH_OWNER}/${env.GH_REPO}/actions/runs/${run.id}/cancel`, { method: 'POST' });
  }
  await env.JOBS.delete(`job:${jobId}`);
  await env.UPLOADS.delete(`projects/${jobId}.zip`);
  return json({ ok: true, cancelled: jobId });
}
