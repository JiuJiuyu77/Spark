//
//  SPBuilder.m
//

#import "SPBuilder.h"
#import "SPCompat.h"
#import "SPToolchainInstaller.h"
#import "SPOutputNaming.h"
#import "SPModels.h"
#import "SPSession.h"
#import "SPToolchain.h"

@implementation SPBuilder

#pragma mark - 脚本生成

+ (NSString *)scriptForProject:(SPProject *)project
                       options:(SPBuildOptions *)options
                       profile:(SPToolchainProfile *)profile
                    backupPath:(NSString *)backupPath {
    NSMutableArray *lines = [NSMutableArray array];

    [lines addObject:@"# Spark 生成脚本 —— 可整段复制到终端里单独运行"];
    [lines addObject:@"set -o pipefail 2>/dev/null || true"];
    [lines addObject:@"export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8"];
    [lines addObject:@"__rb_begin=$(date +%s)"];
    [lines addObject:@"say() { printf '\\033[1;36m==> %s\\033[0m\\n' \"$1\"; }"];
    [lines addObject:@"ok()  { printf '\\033[1;32m[ok] %s\\033[0m\\n' \"$1\"; }"];
    [lines addObject:@"warn(){ printf '\\033[1;33m[!] %s\\033[0m\\n' \"$1\"; }"];

    // ---- 环境 ----
    [lines addObject:@"say '准备构建环境'"];
    NSDictionary *env = [options makeEnvironment];
    NSDictionary *extra = [profile extraEnvironment];
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:env];
    [all addEntriesFromDictionary:extra];
    for (NSString *pair in [SPUtil envPairsFromDictionary:all]) {
        NSRange r = [pair rangeOfString:@"="];
        NSString *k = [pair substringToIndex:r.location];
        NSString *v = [pair substringFromIndex:r.location + 1];
        [lines addObject:[NSString stringWithFormat:@"export %@=%@", k, [SPUtil shellQuote:v]]];
    }

    // ---- 内置工具链（ipa 里的，首启展开到 Documents/Spark/Toolchain）----
    // 结构与 CodexApp/TheosRuntime 一致：rootfs 形态
    //   bin/  usr/bin/  usr/lib/  theos/
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    if (inst.isInstalled) {
        NSString *root = inst.installRoot;
        [lines addObject:[NSString stringWithFormat:@"export SPARK_TC=%@", [SPUtil shellQuote:root]]];
        // PATH：usr/bin 优先（clang-16 / ld64 / ldid / make / dpkg-deb / perl 都在这）
        [lines addObject:@"[ -d \"$SPARK_TC/usr/bin\" ] && export PATH=\"$SPARK_TC/usr/bin:$SPARK_TC/bin:$PATH\""];
        [lines addObject:@"[ -d \"$SPARK_TC/bin\" ] && export PATH=\"$SPARK_TC/bin:$PATH\""];
        // 动态库：clang-16 是薄壳，真正的代码在 usr/lib/llvm-16/lib/libLLVM-16.dylib
        [lines addObject:@"TC_LIBS=\"$SPARK_TC/usr/lib:$SPARK_TC/usr/lib/llvm-16/lib\""];
        [lines addObject:@"[ -d \"$SPARK_TC/usr/lib\" ] && export LD_LIBRARY_PATH=\"$TC_LIBS:${LD_LIBRARY_PATH:-}\""];
        [lines addObject:@"[ -d \"$SPARK_TC/usr/lib\" ] && export DYLD_LIBRARY_PATH=\"$TC_LIBS:${DYLD_LIBRARY_PATH:-}\""];
        // perl 模块：logos.pl 预处理 .x 必需
        [lines addObject:@"[ -d \"$SPARK_TC/usr/lib/perl5\" ] && export PERL5LIB=\"$SPARK_TC/usr/lib/perl5:${PERL5LIB:-}\""];
        // THEOS 位置随运行时结构不同，判定条件是
        // 「有 makefiles 且 sdks 里有真实 SDK」。
        //
        // 只判 common.mk 会踩坑：Rein 对齐包里
        // theos-root/theos/sdks 只有一个 .keep 占位，
        // 选中它之后 make 会报「找不到 SDK」。
        // theos-full 才带真 SDK，所以排在最前。
        // SDK 可能在 $THEOS/sdks，也可能独立在 $SPARK_TC/sdks（Rein 布局）。
        // 判定条件要同时接受两种，否则会跳过真正能用的 theos。
        [lines addObject:@"for t in \"$SPARK_TC/theos\" \"$SPARK_TC/theos-root/theos\" "
                      "\"$SPARK_TC/theos-full\" \"$SPARK_TC/TheosRuntime/theos\"; do "
                      "[ -f \"$t/makefiles/common.mk\" ] || continue; "
                      "{ ls \"$t\"/sdks/iPhoneOS*.sdk >/dev/null 2>&1 || "
                      "ls \"$SPARK_TC\"/sdks/iPhoneOS*.sdk >/dev/null 2>&1; } || continue; "
                      "export THEOS=\"$t\"; break; done"];
        // SDK 在顶层时，把它软链进 $THEOS/sdks，让 make 找得到
        [lines addObject:@"if [ -d \"$SPARK_TC/sdks\" ] && [ -n \"${THEOS:-}\" ]; then "
                      "mkdir -p \"$THEOS/sdks\"; "
                      "for s in \"$SPARK_TC\"/sdks/iPhoneOS*.sdk; do "
                      "[ -d \"$s\" ] || continue; "
                      "ln -sfn \"$s\" \"$THEOS/sdks/$(basename \"$s\")\" 2>/dev/null || true; "
                      "done; fi"];
        [lines addObject:@"[ -n \"${THEOS:-}\" ] || warn '没找到带 SDK 的 theos 目录'"];
    }

    NSString *pathPrefix = [[SPToolchain shared] pathPrefixForProfile:profile];
    if (pathPrefix.length) {
        [lines addObject:[NSString stringWithFormat:@"export PATH=%@:\"$PATH\"", [SPUtil shellQuote:pathPrefix]]];
    }

    // OLLVM 时把 CC/CXX 指向混淆编译器
    if (options.useOLLVM && profile.ollvmRoot.length) {
        NSString *clang = [profile.ollvmRoot stringByAppendingPathComponent:@"bin/clang"];
        NSString *clangxx = [profile.ollvmRoot stringByAppendingPathComponent:@"bin/clang++"];
        [lines addObject:[NSString stringWithFormat:@"export CC=%@ CXX=%@", [SPUtil shellQuote:clang], [SPUtil shellQuote:clangxx]]];
        // Theos 用 TARGET 驱动，额外让 _CC/_CXX 生效
        [lines addObject:[NSString stringWithFormat:@"export _CC=%@ _CXX=%@", [SPUtil shellQuote:clang], [SPUtil shellQuote:clangxx]]];
    }

    // ---- 工具链自检 ----
    [lines addObject:@"say '工具链自检'"];
    [lines addObject:@"ok \"内置工具链 $([ -d \"$SPARK_TC/usr/bin\" ] || [ -d \"$SPARK_TC/bin\" ] && echo 就绪 || echo 未就绪)\""];
    [lines addObject:@"for t in make ldid; do command -v $t >/dev/null 2>&1 && ok \"$t $(command -v $t)\" || warn \"缺少 $t\"; done"];
    [lines addObject:@"CCBIN=\"${CA_TOOL_OLLVM_CLANG:-clang}\"; \"$CCBIN\" --version >/dev/null 2>&1 && ok \"编译器 $($CCBIN --version | head -1)\" || warn \"编译器不可用: $CCBIN\""];
    if (options.useOLLVM) {
        [lines addObject:@"command -v clang >/dev/null 2>&1 && ok \"clang $(command -v clang)\" || warn 'OLLVM clang 不在 PATH'"];
    }

    // ---- SDK ----
    if (profile.sdkPath.length) {
        [lines addObject:@"[ -d \"$THEOS_SDK\" ] && ok \"SDK $THEOS_SDK\" || warn \"SDK 不存在: $THEOS_SDK\""];
    }

    // ---- 进入项目 ----
    [lines addObject:[NSString stringWithFormat:@"cd %@ || { echo '项目目录不存在'; exit 2; }", [SPUtil shellQuote:project.path]]];
    [lines addObject:@"say \"工作目录 $(pwd)\""];

    // ---- 清理 ----
    if (options.cleanBeforeBuild) {
        [lines addObject:@"say '清理旧产物'"];
        [lines addObject:@"rm -rf .theos/_ packages .theos/obj 2>/dev/null || true"];
        if (backupPath.length) {
            [lines addObject:[NSString stringWithFormat:@"mkdir -p %@ && cp -R Packages %@/ 2>/dev/null || true",
                              [SPUtil shellQuote:backupPath], [SPUtil shellQuote:backupPath]]];
        }
    }

    // ---- 构建 ----
    NSArray *args = [options makeArguments];
    NSMutableArray *quoted = [NSMutableArray array];
    for (NSString *a in args) [quoted addObject:[SPUtil shellQuote:a]];
    NSString *makeCmd = [@"make " stringByAppendingString:[quoted componentsJoinedByString:@" "]];

    // Rein 经验：真 root 下 Theos 的 fakeroot 是空壳，可显式关掉
    [lines addObject:@""];
    [lines addObject:@"if [ \"$(id -u)\" = \"0\" ]; then ok '当前是 root，跳过 fakeroot 包装'; export THEOS_USE_FAKEROOT=0; fi"];
    [lines addObject:@"export COPYFILE_DISABLE=1"];
    // xz -1 是速度/体积平衡点（默认 -6 在手机上慢得多）
    [lines addObject:@"export THEOS_PLATFORM_DEB_COMPRESSION_LEVEL=1"];

    // A6：内存遥测（Rein 的 boot.js 每 30s 打 rss/heap，这里跟着 make 一起跑）
    [lines addObject:@"memwatch() { while kill -0 $$ 2>/dev/null; do "
                     "  if [ -r /proc/meminfo ]; then "
                     "    awk \'/MemAvailable/{printf \"    [mem] 可用 %d MB\\n\", $2/1024}\' /proc/meminfo; "
                     "  else "
                     "    vm_stat 2>/dev/null | awk \'/Pages free/{gsub(\"\\.\",\"\",$3); printf \"    [mem] 可用 %d MB\\n\", $3*16384/1048576}\'; "
                     "  fi; sleep 15; done; }"];
    [lines addObject:@"memwatch & MEMPID=$!"];
    [lines addObject:@"say '开始编译'"];
    [lines addObject:[NSString stringWithFormat:@"echo '+ %@'", makeCmd]];
    [lines addObject:@"__rb_start=$(date +%s)"];
    [lines addObject:makeCmd];

    // ---- 签名 ----
    if (options.signWithLdid) {
        [lines addObject:@"if command -v ldid >/dev/null 2>&1; then"];
        [lines addObject:@"  say '补签（ldid -S）'"];
        [lines addObject:@"  find .theos/obj -name '*.dylib' -o -name '*.app' -prune 2>/dev/null | while read f; do ldid -S \"$f\" 2>/dev/null && ok \"sign $f\" || true; done"];
        [lines addObject:@"else"];
        [lines addObject:@"  warn '没有 ldid，跳过补签'"];
        [lines addObject:@"fi"];
    }

    // ---- 产物 ----
    [lines addObject:@"say '收集产物'"];
    [lines addObject:@"ls -lh packages/*.deb .theos/_/ 2>/dev/null | sed 's/^/    /' || true"];
    // 产物自检：拆开 deb 看结构
    [lines addObject:@"for d in packages/*.deb; do"];
    [lines addObject:@"  [ -f \"$d\" ] || continue"];
    [lines addObject:@"  if command -v dpkg-deb >/dev/null 2>&1; then"];
    [lines addObject:@"    ok \"校验 $(basename \"$d\")\""];
    [lines addObject:@"    dpkg-deb -I \"$d\" 2>/dev/null | grep -E 'Package:|Version:|Architecture:' | sed 's/^/      /' || true"];
    [lines addObject:@"  fi"];
    [lines addObject:@"done"];
    [lines addObject:@"__rb_end=$(date +%s)"];
    [lines addObject:@"ok \"用时 $((__rb_end - __rb_begin)) 秒\""];

    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - 产物收集

+ (NSArray<NSString *> *)collectArtifactsInProject:(NSString *)projectPath
                                             since:(NSDate *)since
                                           options:(SPBuildOptions *)options {
    NSMutableArray *out = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *dirs = @[@"packages", @".theos", @".theos/_"];
    NSTimeInterval cutoff = [since timeIntervalSince1970] - 2.0; // 容忍时钟差

    for (NSString *rel in dirs) {
        NSString *dir = [projectPath stringByAppendingPathComponent:rel];
        NSArray *items = [fm contentsOfDirectoryAtPath:dir error:NULL];
        if (!items) continue;
        for (NSString *name in items) {
            NSString *full = [dir stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            [fm fileExistsAtPath:full isDirectory:&isDir];
            if (isDir && ![name hasSuffix:@".app"]) continue;
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
            NSDate *mtime = attrs[NSFileModificationDate];
            if (mtime && [mtime timeIntervalSince1970] < cutoff) continue;
            if ([name hasSuffix:@".deb"] || [name hasSuffix:@".app"] || [name hasSuffix:@".dylib"] ||
                [name hasSuffix:@".tipa"] || [name hasSuffix:@".zip"]) {
                [out addObject:full];
            }
        }
    }
    // deb 优先
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL da = [a hasSuffix:@".deb"], db = [b hasSuffix:@".deb"];
        if (da != db) return da ? NSOrderedAscending : NSOrderedDescending;
        return [b compare:a];
    }];
}

#pragma mark - 失败诊断

+ (NSString *)diagnoseFailureFromLines:(NSArray<SPLogLine *> *)lines {
    // 只扫后面 300 行
    NSArray *tail = lines.count > 300 ? [lines subarrayWithRange:NSMakeRange(lines.count - 300, 300)] : lines;
    NSMutableString *blob = [NSMutableString string];
    for (SPLogLine *l in tail) { [blob appendString:l.text]; [blob appendString:@"\n"]; }
    NSString *s = blob.lowercaseString;

    struct { const char *needle; const char *hint; } rules[] = {
        {"no such file or directory: 'make'", "找不到 make：Theos 没装好，或 PATH 里没有 theos/bin。"},
        {"theos/makefiles", "THEOS 路径不对：找不到 Theos 的 makefiles 目录。"},
        {"sdk", "找不到 SDK：检查 SDK 名称是否与 theos/sdks 里的目录一致。"},
        {"logos", "Logos 预处理失败：检查 .x 文件里的 %hook/%orig 语法。"},
        {"error: expected", "C 语法错误：看上面第一个 error 行。"},
        {"fatal error: '", "头文件缺失：检查 SDK 或 vendor/include 是否包含对应头文件。"},
        {"ld: library not found", "链接不到库：检查 xxx_LIBRARIES 或 .tbd 是否在 SDK/vendor 里。"},
        {"undefined symbols", "缺少实现或库：看 undefined symbol 名字，补上对应框架/源文件。"},
        {"code signature", "签名失败：确认 ldid 可执行且路径有权限。"},
        {"permission denied", "权限不足：真机编译时项目目录需要在 /var/mobile 下且可写。"},
        {"killed", "进程被杀：多半是内存不足，试试关掉 -j 并行或改用远程/CI 构建。"},
        {"theos_package_scheme", "包格式参数问题：rootless 需要较新的 Theos。"},
    };
    for (size_t i = 0; i < sizeof(rules) / sizeof(rules[0]); i++) {
        if ([s rangeOfString:[NSString stringWithUTF8String:rules[i].needle]].location != NSNotFound) {
            return [NSString stringWithUTF8String:rules[i].hint];
        }
    }
    return nil;
}

#pragma mark - 执行

+ (SPSession *)buildProject:(SPProject *)project
                    options:(SPBuildOptions *)options
                    profile:(SPToolchainProfile *)profile
                     onLine:(void (^)(NSString *, SPLogLevel))onLine
                   onFinish:(void (^)(SPJob *))onFinish {
    SPJob *job = [SPJob new];
    job.projectPath = project.path;
    job.projectName = project.name;
    job.options = options;
    job.target = profile.target;
    job.state = SPJobStateRunning;

    NSMutableArray<SPLogLine *> *captured = [NSMutableArray array];

    NSString *script = [self scriptForProject:project options:options profile:profile
                                   backupPath:[project.path stringByAppendingPathComponent:@"_rb_backup"]];

    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    [env addEntriesFromDictionary:[profile extraEnvironment]];
    if (profile.target == SPBuildTargetRemote && profile.sshHost.length) {
        // 远程：生成一个压缩脚本，scp 过去再执行（避免嵌套 heredoc 引号地狱）
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"rb-%@.sh", [SPUtil timestampSlug]]];
        [script writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *remoteTmp = [NSString stringWithFormat:@"/tmp/rb-%@.sh", [SPUtil timestampSlug]];
        NSString *sshBase = [NSString stringWithFormat:@"-p %ld -o StrictHostKeyChecking=no -o ConnectTimeout=10",
                             (long)profile.sshPort];
        NSString *dest = [NSString stringWithFormat:@"%@@%@:%@", profile.sshUser, profile.sshHost, remoteTmp];
        NSMutableString *wrapped = [NSMutableString string];
        [wrapped appendString:[NSString stringWithFormat:@"scp %@ %@ %@ && ssh %@ %@@%@ 'sh %@; ec=$?; rm -f %@; exit $ec'\n",
                              sshBase, [SPUtil shellQuote:tmp], [SPUtil shellQuote:dest],
                              sshBase, profile.sshUser, profile.sshHost, remoteTmp, remoteTmp]];
        [wrapped appendString:[NSString stringWithFormat:@"rc=$?; rm -f %@; exit $rc\n", [SPUtil shellQuote:tmp]]];
        script = wrapped;
    }

    SPSession *session = [[SPSession alloc] initWithEnvironment:env workingDirectory:project.path];

    // 16KB 行内的高亮判断
    session.onLine = ^(NSString *line, SPLogLevel level) {
        SPLogLevel lv = level;
        NSString *low = line.lowercaseString;
        if ([low rangeOfString:@"error:"].location != NSNotFound || [low rangeOfString:@"错误"].location != NSNotFound)
            lv = SPLogLevelErr;
        else if ([line hasPrefix:@"==>"] || [line hasPrefix:@"[ok]"] || [line hasPrefix:@"[!]"])
            lv = SPLogLevelStep;
        @synchronized (captured) { [captured addObject:[SPLogLine lineWithText:line level:lv]]; }
        if (onLine) onLine(line, lv);
    };

    session.onFinish = ^(SPCommandResult *r) {
        job.finishedAt = [NSDate date];
        job.exitCode = r.exitCode;
        @synchronized (captured) { job.lines = [captured copy]; }

        if (r.cancelled) job.state = SPJobStateCancelled;
        else if (r.ok) job.state = SPJobStateSucceeded;
        else job.state = SPJobStateFailed;

        if (job.state == SPJobStateFailed) {
            job.failureHint = r.launchError.localizedDescription ?: [self diagnoseFailureFromLines:job.lines];
            if (r.launchError && onLine) onLine(r.launchError.localizedDescription, SPLogLevelErr);
            if (!job.failureHint) job.failureHint = @"编译失败，请查看上方最后几行 error 输出。";
        }

        NSArray *arts = [self collectArtifactsInProject:project.path since:job.startedAt options:options];
        job.artifacts = arts;
        for (NSString *a in arts) {
            if ([a hasSuffix:@".deb"] || [a hasSuffix:@".app"] || [a hasSuffix:@".tipa"]) { job.bundlePath = a; break; }
        }
        if (!job.bundlePath && arts.count) job.bundlePath = arts.firstObject;

        if (onFinish) onFinish(job);
    };

    [session runShell:script];
    return session;
}

+ (void)cancelSession:(SPSession *)session { [session cancel]; }

@end
