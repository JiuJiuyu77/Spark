//
//  SPSelfTest.m
//

#import "SPSelfTest.h"
#import "SPCompat.h"
#import "SPPrivileged.h"
#import "SPToolchain.h"
#import "SPToolchainInstaller.h"
#import "SPSession.h"
#import "SPStore.h"

@interface SPSelfTest ()
@property (nonatomic, assign) BOOL running;
@end

@implementation SPSelfTestStep
@end

@implementation SPSelfTest

- (SPSelfTestStep *)step:(SPSelfTestStage)st
                   title:(NSString *)title
                  passed:(BOOL)passed
                  detail:(NSString *)detail
                    hint:(NSString *)hint {
    SPSelfTestStep *s = [SPSelfTestStep new];
    s.stage = st;
    s.title = title;
    s.passed = passed;
    s.detail = detail;
    s.hint = hint;
    return s;
}

- (void)runWithLog:(void (^)(NSString *))logHandler
        stepUpdate:(void (^)(SPSelfTestStep *))stepUpdate
        completion:(void (^)(BOOL, NSArray<SPSelfTestStep *> *, NSString *))completion {
    if (self.running) return;
    self.running = YES;

    NSMutableArray<SPSelfTestStep *> *steps = [NSMutableArray array];

    void (^emit)(SPSelfTestStep *) = ^(SPSelfTestStep *s) {
        @synchronized (steps) { [steps addObject:s]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (stepUpdate) stepUpdate(s);
            if (logHandler) logHandler([NSString stringWithFormat:@"%@ %@%@",
                s.passed ? @"[ok]" : @"[x]",
                s.title,
                s.detail.length ? [NSString stringWithFormat:@"：%@", s.detail] : @""]);
        });
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        SPToolchainInstaller *inst = [SPToolchainInstaller shared];

        // ── 1. 环境 ──
        uid_t uid = getuid();
        // 身份只是信息，不是通过条件。
        // Rein 也跑在 uid=501 下，靠的是自带运行时 + 自带 shell，
        // 而不是进程本身有 root。真正决定成败的是下面「子进程身份」那一步。
        emit([self step:SPSelfTestStageEnv title:@"进程身份" passed:YES
                 detail:[NSString stringWithFormat:@"uid=%d（%@）",
                         (int)uid, uid == 0 ? @"root" : @"mobile，正常"]
                   hint:nil]);

        NSString *tmp = NSTemporaryDirectory();
        NSString *probe = [tmp stringByAppendingPathComponent:@"spark-selftest-probe"];
        NSError *werr = nil;
        BOOL writable = [@"probe" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:&werr];
        [fm removeItemAtPath:probe error:NULL];
        emit([self step:SPSelfTestStageEnv title:@"临时目录可写" passed:writable
                 detail:tmp hint:writable ? nil : (werr.localizedDescription ?: @"无法写入临时目录")]);

        // ── 1.5 shell 能否真的启动 ──
        // 「退出码 -1、耗时 0 秒」几乎都是这一步失败：
        // posix_spawn 拒绝了 /bin/sh（沙盒不允许执行系统二进制），
        // 子进程根本没起来。必须单独验证，否则用户只会看到 -1。
        __block BOOL shellOK = NO;
        __block NSString *shellDetail = nil;

        // ── 1.4 子进程身份 ──
        // 主进程拿不到 root 不代表编译一定失败：TrollStore 环境下，
        // 用 platform-application 签名的 App 启动的子进程有可能继承
        // 「platform」身份（比 mobile 高），这才是能读 SDK / 写系统路径的关键。
        // 这里实际跑一次 `id -u`，把子进程的真实 uid 打出来。
        {
            NSString *sh = [SPSession resolveShell];
            if (sh.length) {
                // 一次跑完所有关键探测，减少子进程启动次数（每次 ~1 秒）
                NSString *probe =
                    @"echo uid=$(id -u); "
                    @"echo gid=$(id -g); "
                    // 能否写系统路径 —— 这才是「有没有特权」的实际判据，
                    // 比只看 uid 更准：有些环境 uid=0 但仍写不了 /usr
                    @"touch /usr/lib/.spark-probe 2>/dev/null && "
                    @"{ echo syswrite=yes; rm -f /usr/lib/.spark-probe; } || echo syswrite=no; "
                    // SDK 目录是否可读（编译要读 SDK 里的头文件与 tbd）
                    @"if [ -r /var/mobile/Documents ]; then echo readprobe=ok; "
                     "else echo readprobe=no; fi; ";
                SPCommandResult *idr = [SPSession runSyncShell:probe
                                                   environment:@{}
                                                          cwd:NSTemporaryDirectory()
                                                      timeout:15];
                NSString *out = [[idr.stdoutText ?: @"" stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];

                // 解析 key=value
                NSMutableDictionary *kv = [NSMutableDictionary dictionary];
                for (NSString *ln in [out componentsSeparatedByString:@"\n"]) {
                    NSArray *parts = [ln componentsSeparatedByString:@"="];
                    if (parts.count == 2) kv[parts[0]] = parts[1];
                }
                NSString *cuid = kv[@"uid"] ?: @"?";
                BOOL childRoot = [cuid isEqualToString:@"0"];
                BOOL sysWrite = [kv[@"syswrite"] isEqualToString:@"yes"];

                // 展示：uid + 能否写系统路径
                NSString *detail = [NSString stringWithFormat:@"uid=%@ · 系统路径%@",
                                    cuid, sysWrite ? @"可写" : @"只读"];

                NSString *hint = nil;
                if (childRoot && sysWrite) {
                    hint = @"子进程是 root 且能写系统路径 —— 编译条件完备";
                } else if (childRoot) {
                    hint = @"子进程是 root，但系统路径只读（可能是只读根文件系统），"
                            "基础编译仍可完成";
                } else {
                    // uid 相同但也不一定是问题：编译全部在 App 包内进行，
                    // 只需要能读包内文件、能在 /var/mobile 下写临时目录
                    hint = [NSString stringWithFormat:
                        @"子进程 uid=%@（与主进程相同）。这不必然导致失败 —— "
                         "编译链路全部在 App 包内（工具/SDK 都在包里），"
                         "产物写到 /var/mobile/Documents 下，都不需要 root。"
                         "如果构建仍失败，看「实际编译」那一步的具体报错。", cuid];
                }

                emit([self step:SPSelfTestStageEnv
                         title:@"子进程身份"
                        passed:YES
                        detail:detail
                          hint:hint]);
                SPLog(@"子进程探测原始输出：%@", out.length ? out : @"(空)");
            } else {
                emit([self step:SPSelfTestStageEnv title:@"子进程身份" passed:NO
                        detail:@"找不到可用的 shell"
                          hint:@"运行时的 helpers/bash 缺失，子进程无法启动"]);
            }
        }

        dispatch_semaphore_t shSem = dispatch_semaphore_create(0);
        SPSession *shProbe = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:tmp];
        shProbe.timeout = 15;
        shProbe.onFinish = ^(SPCommandResult *r) {
            shellOK = (r.exitCode == 0);
            if (!shellOK) {
                shellDetail = r.launchError.localizedDescription
                           ?: [NSString stringWithFormat:@"退出码 %ld", (long)r.exitCode];
            }
            dispatch_semaphore_signal(shSem);
        };
        [shProbe runShell:@"echo spark-shell-ok"];
        dispatch_semaphore_wait(shSem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));

        emit([self step:SPSelfTestStageEnv title:@"shell 可启动" passed:shellOK
                 detail:shellOK ? [SPSession resolveShell] : (shellDetail ?: @"超时")
                   hint:shellOK ? nil
                        : @"posix_spawn 被拒绝：运行时里的 bash 可能没打进 ipa，"
                          @"或 App 不是以 root 运行。检查 设置 → 工具链 是否含 helpers/bash"]);

        // ── 2. 工具链 ──
        NSString *bin = inst.binDir;
        NSArray *tools = @[@"clang-16", @"ld64", @"ldid", @"make", @"perl"];
        NSMutableArray *missing = [NSMutableArray array];
        for (NSString *t in tools) {
            if (![fm isExecutableFileAtPath:[bin stringByAppendingPathComponent:t]]) {
                // 有些包把 ldid 放在 bin/ 而不是 usr/bin/
                BOOL alt = [fm isExecutableFileAtPath:
                            [[inst baseBinDir] stringByAppendingPathComponent:t]];
                if (!alt) [missing addObject:t];
            }
        }
        emit([self step:SPSelfTestStageToolchain title:@"编译工具齐全"
                 passed:(missing.count == 0)
                 detail:missing.count ? [missing componentsJoinedByString:@"、"] : bin
                   hint:missing.count ? @"工具链不完整：设置 → 工具链 → 重新展开内置工具链" : nil]);

        // ── 3. Theos ──
        NSString *theos = inst.theosPath;
        BOOL hasMk = [fm fileExistsAtPath:[theos stringByAppendingPathComponent:@"makefiles/common.mk"]];
        BOOL hasLogos = [fm fileExistsAtPath:[theos stringByAppendingPathComponent:@"bin/logos.pl"]];
        emit([self step:SPSelfTestStageTheos title:@"Theos makefiles"
                 passed:(hasMk && hasLogos)
                 detail:theos
                   hint:(hasMk && hasLogos) ? nil
                        : @"THEOS 目录不完整：缺 makefiles/common.mk 或 bin/logos.pl"]);

        // ── 3.1 Theos vendor 标记 ──
        // master/rules.mk 会检查 vendor/include/.git 与 vendor/lib/.git，
        // 缺一个就直接 $(error) 中止 —— 但报错文案说的是
        // 「vendor 目录缺失」，很容易被理解成目录不存在。
        {
            NSString *vi = [theos stringByAppendingPathComponent:@"vendor/include"];
            NSString *vl = [theos stringByAppendingPathComponent:@"vendor/lib"];
            BOOL viOK = [fm fileExistsAtPath:[vi stringByAppendingPathComponent:@".git"]];
            BOOL vlOK = [fm fileExistsAtPath:[vl stringByAppendingPathComponent:@".git"]];
            emit([self step:SPSelfTestStageTheos
                     title:@"vendor 标记"
                    passed:(viOK && vlOK)
                    detail:[NSString stringWithFormat:@"include:%@ lib:%@",
                            viOK ? @"✓" : @"✗", vlOK ? @"✓" : @"✗"]
                      hint:(viOK && vlOK) ? nil
                           : @"Theos 用 vendor/*/.git 判断 vendor 是否就绪，"
                             @"缺了会让 make 报「vendor 目录缺失」。重新展开工具链可修复。"]);
        }

        // ── 3.2 编译链关键工具逐个点名 ──
        {
            
            NSArray *tools = @[@"clang-16", @"ld64", @"ldid", @"make",
                               @"dpkg-deb", @"perl", @"strip", @"ar"];
            NSMutableArray *missing = [NSMutableArray array];
            NSMutableArray *found = [NSMutableArray array];
            for (NSString *t in tools) {
                NSString *p1 = [inst.binDir stringByAppendingPathComponent:t];
                NSString *p2 = [inst.installRoot stringByAppendingPathComponent:
                                [@"helpers" stringByAppendingPathComponent:t]];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:p1 isDirectory:&isDir] && !isDir) { [found addObject:t]; continue; }
                if ([fm fileExistsAtPath:p2 isDirectory:&isDir] && !isDir) { [found addObject:t]; continue; }
                [missing addObject:t];
            }
            emit([self step:SPSelfTestStageToolchain
                     title:@"编译链工具"
                    passed:(missing.count == 0)
                    detail:[NSString stringWithFormat:@"%lu/%lu 就绪",
                            (unsigned long)found.count, (unsigned long)tools.count]
                      hint:missing.count ? [NSString stringWithFormat:
                            @"缺少：%@。这些是 make 各阶段要用的，缺任何一个都会在"
                             "中途报错（dpkg-deb 缺了就无法产出 .deb）。",
                            [missing componentsJoinedByString:@"、"]] : nil]);
        }

        // ── 3.3 ld64 的动态库依赖（libxar / libtapi）──
        // ld64 是链接阶段的核心，它自己依赖 @rpath/libxar.1.dylib
        // 和 libtapi.dylib。这两个库少了，链接会以
        // 「library.mk:37 Error 2」这种看不出原因的方式失败。
        {
            NSString *ld = [inst.binDir stringByAppendingPathComponent:@"ld64"];
            NSString *ldir = inst.libDir;
            NSArray *deps = @[@"libxar.1.dylib", @"libtapi.dylib"];
            NSMutableArray *miss = [NSMutableArray array];
            for (NSString *d in deps) {
                NSString *dp = [ldir stringByAppendingPathComponent:d];
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:dp isDirectory:&isDir] || isDir) [miss addObject:d];
            }
            BOOL ldOK = [fm fileExistsAtPath:ld isDirectory:NULL];
            emit([self step:SPSelfTestStageToolchain
                     title:@"链接器依赖"
                    passed:(ldOK && miss.count == 0)
                    detail:miss.count ? [NSString stringWithFormat:@"缺 %@",
                                         [miss componentsJoinedByString:@"、"]]
                                      : @"libxar + libtapi 就绪"
                      hint:(ldOK && miss.count == 0) ? nil
                           : @"ld64 找不到这两个库时，链接只会给一句 "
                             @"「Error 2」，看不出是缺库。重新展开工具链可修复。"]);
        }

        // ── 3.4 内置附加工具（对照 Rein 的运行时清单）──
        {
            NSArray *extras = @[@"ollvm", @"reverse", @"python-runtime", @"node22", @"pnpm"];
            NSMutableArray *have = [NSMutableArray array];
            NSMutableArray *lack = [NSMutableArray array];
            NSString *root = inst.installRoot;
            for (NSString *e in extras) {
                NSString *pth = [root stringByAppendingPathComponent:e];
                if ([fm fileExistsAtPath:pth]) [have addObject:e]; else [lack addObject:e];
            }
            emit([self step:SPSelfTestStageToolchain
                     title:@"附加工具链"
                    passed:YES
                    detail:have.count ? [have componentsJoinedByString:@"、"] : @"无"
                      hint:lack.count ? [NSString stringWithFormat:
                            @"未内置：%@。不影响基础编译，只影响混淆/逆向等附加功能。",
                            [lack componentsJoinedByString:@"、"]] : nil]);
        }

        // ── 4. SDK ──
        NSString *sdksDir = [theos stringByAppendingPathComponent:@"sdks"];
        NSMutableArray *sdks = [NSMutableArray array];
        for (NSString *n in [fm contentsOfDirectoryAtPath:sdksDir error:NULL] ?: @[]) {
            if (![n hasPrefix:@"iPhoneOS"] || ![n hasSuffix:@".sdk"]) continue;
            // 空目录（只有 .keep）不算
            BOOL hasSettings = [fm fileExistsAtPath:
                [[sdksDir stringByAppendingPathComponent:n] stringByAppendingPathComponent:@"SDKSettings.json"]];
            if (hasSettings) [sdks addObject:n];
        }
        emit([self step:SPSelfTestStageSDK title:@"可用 SDK"
                 passed:(sdks.count > 0)
                 detail:sdks.count ? [sdks componentsJoinedByString:@", "] : @"无"
                   hint:sdks.count ? nil : @"SDK 缺失或为空：设置 → 工具链 → 重新展开"]);

        // 前置失败就不用往下跑了
        BOOL preOK = YES;
        @synchronized (steps) {
            for (SPSelfTestStep *s in steps) if (!s.passed) preOK = NO;
        }
        if (!preOK) {
            [self finish:steps ok:NO completion:completion];
            return;
        }

        // ── 5. 生成最小工程 ──
        NSString *work = [[[SPStore shared] baseDirectory]
                          stringByAppendingPathComponent:@"selftest/tweak"];
        [fm removeItemAtPath:work error:NULL];
        [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:NULL];

        NSString *mk = @"ARCHS = arm64\n"
                        "TARGET = iphone:clang:latest:15.0\n"
                        "INSTALL_TARGET_PROCESSES = SpringBoard\n"
                        "\n"
                        "include $(THEOS)/makefiles/common.mk\n"
                        "\n"
                        "TWEAK_NAME = SparkSelfTest\n"
                        "SparkSelfTest_FILES = Tweak.x\n"
                        "\n"
                        "include $(THEOS_MAKE_PATH)/tweak.mk\n";
        NSString *x = @"%hook NSObject\n"
                       "- (id)description { return %orig; }\n"
                       "%end\n";
        NSString *ctrl = @"Package: com.huging.spark.selftest\n"
                          "Name: Spark Self Test\n"
                          "Version: 0.0.1\n"
                          "Architecture: iphoneos-arm\n"
                          "Description: Spark 自检用\n"
                          "Maintainer: Spark\n"
                          "Author: Spark\n"
                          "Section: Tweaks\n";
        BOOL wrote = [mk writeToFile:[work stringByAppendingPathComponent:@"Makefile"]
                          atomically:YES encoding:NSUTF8StringEncoding error:NULL]
                  && [x writeToFile:[work stringByAppendingPathComponent:@"Tweak.x"]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL]
                  && [ctrl writeToFile:[work stringByAppendingPathComponent:@"control"]
                            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        emit([self step:SPSelfTestStageScaffold title:@"生成测试工程" passed:wrote
                 detail:work.lastPathComponent
                   hint:wrote ? nil : @"无法写入测试工程目录"]);

        if (!wrote) {
            [self finish:steps ok:NO completion:completion];
            return;
        }

        // ── 6. 实际编译 ──
        // 精简版脚本：只跑 make，不做混淆/签名等额外步骤，
        // 目的是验证「工具链能否真的编出 .deb」
        NSString *cmd = [NSString stringWithFormat:
            @"set -o pipefail 2>/dev/null || true\n"
             "export THEOS=%@\n"
             // PATH 必须包含三处，否则 make 找不到关键工具：
             //   %@ = theos-root/usr/bin   （clang-16 / ld64 / make）
             //   installRoot/helpers       （bash / dpkg-deb / fakeroot —— 打包必需）
             //   theos/bin                 （logos.pl —— .x 预处理必需）
             "export PATH=\"%@:%@/helpers:%@/bin:$PATH\"\n"
             "export LD_LIBRARY_PATH=\"%@\"\n"
             "export DYLD_LIBRARY_PATH=\"%@\"\n"
             "export PERL5LIB=\"%@\"\n"
             "export ARCHS=arm64 TARGET=iphone:clang:latest:15.0\n"
             "export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8\n"
             "cd %@\n"
             "echo \"==> PWD=$(pwd)\"\n"
             "echo \"==> THEOS=$THEOS\"\n"
             "echo \"==> clang=$(command -v clang-16 || echo none)\"\n"
             "echo \"==> uid=$(id -u)\"\n"
             // -d：把实际执行的命令打出来。之前只看到
             // 「lib.mk:52 ... Error 2」，看不到是哪条 ld 命令失败、缺了什么。
             "make package FINALPACKAGE=1 -d 2>&1\n"
             "MK=$?\n"
             "echo \"==> make exit=$MK\"\n"
             "ls -l packages/*.deb 2>/dev/null || echo \"==> 没有产物\"\n"
             // 关键：把 make 的退出码作为整个脚本的退出码带出去。
             // 以前最后一句是 `ls ... || echo`，它永远返回 0，
             // 于是外面看到的 exitCode 恒为 0，make 失败也被判成「成功」。
             "exit $MK\n",
            [SPUtil shellQuote:theos],
            [SPUtil shellQuote:bin],
            [SPUtil shellQuote:inst.installRoot],
            [SPUtil shellQuote:theos],
            [SPUtil shellQuote:inst.libDir],
            [SPUtil shellQuote:inst.libDir],
            [SPUtil shellQuote:inst.perl5Dir],
            [SPUtil shellQuote:work]];

        __block NSMutableString *buildLog = [NSMutableString string];
        __block BOOL buildOK = NO;
        __block NSString *buildErr = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        SPSession *s = [[SPSession alloc] initWithEnvironment:@{}
                                              workingDirectory:work];
        s.timeout = 300;
        s.onLine = ^(NSString *line, SPLogLevel lv) {
            @synchronized (buildLog) {
                [buildLog appendFormat:@"%@\n", line ?: @""];
            }
            if (logHandler) dispatch_async(dispatch_get_main_queue(), ^{ logHandler(line ?: @""); });
        };
        s.onFinish = ^(SPCommandResult *r) {
            // 退出码优先，但双保险：日志里若明确写了 `==> make exit=N`，以 N 为准
            // （某些 shell 包装会把 exit 吃掉，只看 exitCode 可能误判）
            NSInteger code = r.exitCode;
            @synchronized (buildLog) {
                NSRange rg = [buildLog rangeOfString:@"==> make exit="];
                if (rg.location != NSNotFound) {
                    NSString *rest = [buildLog substringFromIndex:NSMaxRange(rg)];
                    NSString *num = [[rest componentsSeparatedByCharactersInSet:
                                      [NSCharacterSet whitespaceAndNewlineCharacterSet]] firstObject];
                    if (num.length) code = num.integerValue;
                }
            }
            buildOK = (code == 0);
            if (!buildOK) {
                NSString *out = r.stdoutText ?: @"";
                if (!out.length) @synchronized (buildLog) { out = [buildLog copy]; }
                // 取最后几行作为错误摘要
                NSArray *lines = [out componentsSeparatedByString:@"\n"];
                NSUInteger from = lines.count > 12 ? lines.count - 12 : 0;
                buildErr = [[lines subarrayWithRange:NSMakeRange(from, lines.count - from)]
                            componentsJoinedByString:@"\n"];
            }
            dispatch_semaphore_signal(sem);
        };
        [s runShell:cmd];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 320 * NSEC_PER_SEC));

        NSString *logText = nil;
        @synchronized (buildLog) { logText = [buildLog copy]; }

        // 判定是否真的产出 .deb（make exit=0 但没产物也算失败）
        NSArray *pkgs = [fm contentsOfDirectoryAtPath:[work stringByAppendingPathComponent:@"packages"]
                                                error:NULL] ?: @[];
        BOOL hasDeb = NO;
        for (NSString *p in pkgs) if ([p hasSuffix:@".deb"]) { hasDeb = YES; break; }

        emit([self step:SPSelfTestStageBuild title:@"实际编译" passed:(buildOK && hasDeb)
                 detail:(buildOK && hasDeb) ? @"make 成功并产出 .deb"
                       : (buildOK ? @"make 成功但没有 .deb" : @"make 失败")
                   hint:(buildOK && hasDeb) ? nil : (buildErr.length > 500
                        ? [buildErr substringFromIndex:buildErr.length - 500] : buildErr)]);

        emit([self step:SPSelfTestStageArtifact title:@"产物校验" passed:hasDeb
                 detail:hasDeb ? [pkgs componentsJoinedByString:@", "] : @"无"
                   hint:hasDeb ? nil : @"编译没有产出 .deb，见上一步的错误"]);

        [self finish:steps ok:(buildOK && hasDeb) completion:completion];
    });
}

- (void)finish:(NSArray<SPSelfTestStep *> *)steps
            ok:(BOOL)ok
    completion:(void (^)(BOOL, NSArray<SPSelfTestStep *> *, NSString *))completion {
    self.running = NO;

    NSMutableArray *fails = [NSMutableArray array];
    @synchronized (steps) {
        for (SPSelfTestStep *s in steps) if (!s.passed) [fails addObject:s];
    }

    NSMutableString *summary = [NSMutableString string];
    if (ok) {
        [summary appendString:@"✓ 全链路正常：工具链、Theos、SDK 都能用，已编出 .deb。"];
    } else {
        [summary appendFormat:@"✗ %lu 项未通过：\n", (unsigned long)fails.count];
        for (SPSelfTestStep *s in fails) {
            [summary appendFormat:@"\n· %@\n  %@\n", s.title, s.hint ?: s.detail ?: @""];
        }
    }

    NSArray *snapshot = nil;
    @synchronized (steps) { snapshot = [steps copy]; }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(ok, snapshot, summary);
    });
}

@end
