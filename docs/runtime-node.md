# 运行时 Node 版本

## 现状（2026-11-15 核查）

| 位置 | 版本 | 说明 |
|---|---|---|
| 本机 iSH/Alpine 3.21 已装 | **v22.23.2** | `apk policy nodejs` 显示 `22.23.2-r0` |
| Alpine 3.21 上游 main | **v22.23.4-r0** | 华为云镜像，可直接 `apk upgrade` |
| Alpine 3.21 的 nodejs-current | **v23.2.0-r1** | 跨大版本，不建议给工具链用 |
| Rein 自带的 node22 | v22.x（App 包内，约 78 MB） | 签名区内，Rein 优先用它 |
| Workbench CI | `actions/setup-node@v4` → **22** | `.github/workflows/*.yml` |

## 升级命令

```sh
# 只升到上游补丁版（22.23.2 → 22.23.4，风险最低）
apk update && apk --no-cache upgrade nodejs npm

# 验证
node --version   # 期望 v22.23.4
```

## 注意

- **不要**贸然升到 `nodejs-current`（23.x）：Rein 的插件体系与 `bin/node22` 都以 22 为基准，
  大版本跨越可能让 pnpm / 原生扩展（`.node`）加载失败。
- Workbench 的纯 JS 部分（`ShareKit` / `ProjectKit`）只用 ES2022 语法，22 与 23 都能跑，
  所以升级不会影响 App 内的判定逻辑。
- 真正影响编译链的是 **Darwin 侧 clang/ld64**，与 Node 版本无关。
