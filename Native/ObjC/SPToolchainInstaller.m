//
//  SPToolchainInstaller.m
//

#import "SPToolchainInstaller.h"
#import "SPCompat.h"

static NSString *const kInstalledVersionKey = @"Spark.toolchainVersion";

@interface SPToolchainInstaller ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) BOOL installing;
@end

@implementation SPToolchainInstaller

+ (instancetype)shared {
    static SPToolchainInstaller *i; static dispatch_once_t once;
    dispatch_once(&once, ^{
        i = [SPToolchainInstaller new];
        i.queue = dispatch_queue_create("com.huging.spark.toolchain", DISPATCH_QUEUE_SERIAL);
    });
    return i;
}

#pragma mark - 路径

- (NSString *)installRoot {
    // **优先直接用 App 包内的运行时，不复制。**
    //
    // 之前一律复制到 Documents：511MB 的内容在首次启动时拷一遍，
    // 既慢（十几秒到几十秒）又占双倍空间（包内 511M + Documents 511M）。
    // 而运行时是只读的，包内路径完全够用。
    //
    // 只有当用户手动导入过外部运行时（Documents 里那份更新/存在），
    // 才用 Documents 的 —— 这样「从文件导入」功能仍然有效。
    NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark/Toolchain"];
    NSFileManager *fm = NSFileManager.defaultManager;

    BOOL docsReady = [fm fileExistsAtPath:[docs stringByAppendingPathComponent:@".installed"]];
    if (docsReady) return docs;

    NSString *bundled = self.bundledRoot;
    if (bundled.length) return bundled;

    return docs;
}

- (NSString *)bundledRoot {
    // 新版：运行时**平铺在 .app 根目录**（与 Rein 一致）
    //   Spark.app/theos-root/  helpers/  sdks/
    NSString *bundle = [NSBundle mainBundle].bundlePath;
    NSString *flatMarker = [bundle stringByAppendingPathComponent:@"theos-root/usr/bin/clang-16"];
    if ([NSFileManager.defaultManager fileExistsAtPath:flatMarker]) return bundle;

    // 兼容旧版：Resources/Toolchain 作为 folder reference 拷进 .app
    NSString *p = [[NSBundle mainBundle] pathForResource:@"Toolchain" ofType:nil];
    if (p) return p;
    p = [bundle stringByAppendingPathComponent:@"Toolchain"];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}

- (BOOL)hasBundledToolchain { return self.bundledRoot != nil; }

/// 运行时结构有两种，统一在这里判定：
///   A. Rein 对齐包（当前使用）：theos-root/{usr/bin,usr/lib}
///                               + theos-full/{makefiles,sdks}
///   B. 早期/CodexApp 形态：     usr/bin + usr/lib + theos/
/// 判错任何一个都会导致「工具链显示就绪但编译失败」。
- (NSString *)binDir {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *rel in @[@"usr/bin", @"theos-root/usr/bin", @"bin"]) {
        NSString *p = [self.installRoot stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:p]) return p;
    }
    return [self.installRoot stringByAppendingPathComponent:@"bin"];
}
- (NSString *)libDir {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *rel in @[@"usr/lib", @"theos-root/usr/lib", @"lib"]) {
        NSString *p = [self.installRoot stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:p]) return p;
    }
    return [self.installRoot stringByAppendingPathComponent:@"lib"];
}
- (NSString *)theosPath {
    NSFileManager *fm = NSFileManager.defaultManager;
    // 顺序与判定都很关键：
    //   · theos-full 优先 —— Rein 对齐包里只有它带真实 SDK
    //   · theos-root/theos 的 sdks 里可能只有 .keep（空目录），
    //     只判 common.mk 存在会选中它，然后在编译时报「找不到 SDK」
    NSArray *cands = @[@"theos", @"theos-full", @"theos-root/theos",
                       @"TheosRuntime/theos", @"theos-min"];

    // SDK 可能在 theos/sdks，也可能独立在顶层 sdks/（Rein 的布局就是这样），
    // 两处都要看，否则会误判「没有可用 SDK」。
    NSArray *sdkDirs = @[
        @"sdks",
        @"theos-full/sdks",
        @"theos/sdks",
        @"theos-root/theos/sdks",
    ];
    BOOL (^hasSDKIn)(NSString *) = ^BOOL(NSString *root) {
        for (NSString *rel in sdkDirs) {
            NSString *dir = [root stringByAppendingPathComponent:rel];
            for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
                if (![name hasPrefix:@"iPhoneOS"] || ![name hasSuffix:@".sdk"]) continue;
                NSString *settings = [[dir stringByAppendingPathComponent:name]
                                      stringByAppendingPathComponent:@"SDKSettings.json"];
                if ([fm fileExistsAtPath:settings]) return YES;
            }
        }
        return NO;
    };

    // 判定顺序：先看**这个候选自己**带不带 SDK，再看整体。
    // 之前只判 hasSDKIn(installRoot)，而 theos-full 的 SDK 在
    // theos-full/sdks 下，不在 installRoot 的任何一个 sdkDirs 里，
    // 于是 theos-full 也被跳过 → 最终报「找不到 SDK」。
    for (NSString *rel in cands) {
        NSString *p = [self.installRoot stringByAppendingPathComponent:rel];
        if (![fm fileExistsAtPath:[p stringByAppendingPathComponent:@"makefiles/common.mk"]]) continue;

        // ① 该 THEOS 自带 sdks/
        NSString *own = [p stringByAppendingPathComponent:@"sdks"];
        for (NSString *name in [fm contentsOfDirectoryAtPath:own error:NULL] ?: @[]) {
            if (![name hasPrefix:@"iPhoneOS"] || ![name hasSuffix:@".sdk"]) continue;
            if ([fm fileExistsAtPath:[[own stringByAppendingPathComponent:name]
                    stringByAppendingPathComponent:@"SDKSettings.json"]]) return p;
        }
        // ② 全局位置（顶层 sdks / theos-full/sdks 等）
        if (hasSDKIn(self.installRoot)) return p;
    }
    // 都不可用：退回第一个有 makefiles 的（让上层报出具体缺什么）
    for (NSString *rel in cands) {
        NSString *p = [self.installRoot stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:[p stringByAppendingPathComponent:@"makefiles/common.mk"]]) return p;
    }
    return [self.installRoot stringByAppendingPathComponent:@"theos"];
}
- (NSString *)baseBinDir    { return [self.installRoot stringByAppendingPathComponent:@"bin"]; }
- (NSString *)perl5Dir      { return [[self libDir] stringByAppendingPathComponent:@"perl5"]; }
- (NSString *)ollvmRoot     { return [self.installRoot stringByAppendingPathComponent:@"ollvm"]; }
- (NSString *)reverseBinDir { return [self.installRoot stringByAppendingPathComponent:@"reverse/bin"]; }


#pragma mark - 状态

- (NSString *)installedVersion {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kInstalledVersionKey];
}

/// 包内 manifest 的 builtAt 作为版本号
- (nullable NSString *)bundledVersion {
    NSString *manifest = [self.bundledRoot stringByAppendingPathComponent:@"manifest.json"];
    NSData *d = [NSData dataWithContentsOfFile:manifest];
    if (!d) return nil;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    return [j isKindOfClass:NSDictionary.class] ? j[@"builtAt"] : nil;
}

- (BOOL)isInstalled {
    NSFileManager *fm = NSFileManager.defaultManager;

    // 包内运行时不需要 .installed 标记：
    // 它随 App 一起装好，判定标准就是「关键文件在不在」。
    // 只有 Documents 里的导入运行时才需要标记。
    BOOL usingBundled = [self.installRoot isEqualToString:self.bundledRoot ?: @""];
    if (!usingBundled) {
        NSString *stamp = [self.installRoot stringByAppendingPathComponent:@".installed"];
        if (![fm fileExistsAtPath:stamp]) return NO;
    }

    // 至少要有 ld64 或 clang，且 Theos makefiles 在
    BOOL hasCompiler = NO;
    for (NSString *d in @[self.binDir, self.baseBinDir]) {
        for (NSString *b in @[@"ld64", @"clang-16", @"clang"]) {
            if ([fm isExecutableFileAtPath:[d stringByAppendingPathComponent:b]]) { hasCompiler = YES; break; }
        }
        if (hasCompiler) break;
    }
    BOOL hasTheos = [fm fileExistsAtPath:[self.theosPath stringByAppendingPathComponent:@"makefiles/common.mk"]];
    return hasCompiler && hasTheos;
}

- (BOOL)installing { return _installing; }

#pragma mark - 安装

- (void)installWithProgress:(SPInstallProgress)progress completion:(SPInstallCompletion)completion {
    SPInstallCompletion done = ^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, err); });
    };

    if (!self.hasBundledToolchain) {
        NSError *e = SPError(SPErrorCodeMissingToolchain,
            @"这个安装包里没有内置工具链（CI 构建时未合并）。请把 Toolchain.zip 放到 App 里，或用「设置 → 工具链 → 从文件导入」。");
        done(NO, e);
        return;
    }
    NSString *want = [self bundledVersion];
    if (self.isInstalled && want && [want isEqualToString:self.installedVersion]) {
        done(YES, nil);
        return;
    }

    self.installing = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        NSError *err = [self expandWithProgress:progress];
        self.installing = NO;
        if (!err) {
            [[NSUserDefaults standardUserDefaults] setObject:want ?: @"1" forKey:kInstalledVersionKey];
        }
        done(err == nil, err);
    });
}

- (void)reinstallWithProgress:(SPInstallProgress)progress completion:(SPInstallCompletion)completion {
    [self uninstall];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInstalledVersionKey];
    [self installWithProgress:progress completion:completion];
}

/// 真正的解包：逐文件复制 + 恢复可执行位 + 建符号链接
- (nullable NSError *)expandWithProgress:(SPInstallProgress)progress {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *src = self.bundledRoot;
    NSString *dst = self.installRoot;

    NSError *err = nil;
    [fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) return err;
    [fm removeItemAtPath:dst error:NULL];
    if (![fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:&err]) return err;

    // 统计文件总数用于进度
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:src];
    NSString *rel;
    while ((rel = [e nextObject])) [entries addObject:rel];
    NSUInteger total = MAX(entries.count, 1);
    NSUInteger idx = 0;
    NSUInteger failedCopies = 0;
    NSError *firstCopyError = nil;

    for (rel in entries) {
        @autoreleasepool {
            NSString *from = [src stringByAppendingPathComponent:rel];
            NSString *to = [dst stringByAppendingPathComponent:rel];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:from isDirectory:&isDir]) continue;

            // 跳过 SDK（不内置）
            if ([rel hasPrefix:@"theos/sdks"]) { [e skipDescendants]; continue; }

            if (isDir) {
                [fm createDirectoryAtPath:to withIntermediateDirectories:YES attributes:nil error:NULL];
            } else {
                [fm createDirectoryAtPath:[to stringByDeletingLastPathComponent]
              withIntermediateDirectories:YES attributes:nil error:NULL];
                [fm removeItemAtPath:to error:NULL];

                // 复制失败**必须**记下来。
                // 之前这里是 copyItemAtPath:error:NULL 且不检查返回值，
                // 结果是「工具链缺文件但装上了标记」。用户看到「已就绪」，
                // 一编译就失败 —— 这类问题极难自查。
                NSError *copyErr = nil;
                if (![fm copyItemAtPath:from toPath:to error:&copyErr]) {
                    failedCopies++;
                    if (!firstCopyError) firstCopyError = copyErr;
                    SPLog(@"[!] 复制失败 %@：%@", rel, copyErr.localizedDescription);
                    if (failedCopies >= 20) {
                        SPLog(@"[!] 复制失败超过 20 个，中止展开");
                        return SPError(SPErrorCodeIO,
                            [NSString stringWithFormat:@"展开工具链失败（已有 %lu 个文件复制失败）：%@",
                             (unsigned long)failedCopies, firstCopyError.localizedDescription]);
                    }
                    continue;
                }
                NSDictionary *attrs = [fm attributesOfItemAtPath:from error:NULL];
                if (attrs) {
                    id perm = attrs[NSFilePosixPermissions];
                    if ([perm isKindOfClass:[NSNumber class]]) {
                        NSMutableDictionary *newAttrs = [NSMutableDictionary dictionary];
                        newAttrs[NSFilePosixPermissions] = (NSNumber *)perm;
                        [fm setAttributes:newAttrs ofItemAtPath:to error:NULL];
                    }
                }
            }
            idx++;
            if (progress && idx % 40 == 0) {
                CGFloat f = (CGFloat)idx / (CGFloat)total;
                progress(f, [NSString stringWithFormat:@"展开工具链 %lu/%lu", (unsigned long)idx, (unsigned long)total]);
            }
        }
        // 让出队列，避免长时间占满
        if (idx % 400 == 0) usleep(1000);
    }

    // 关键：给 bin/ 下所有文件加可执行位
    if (progress) progress(0.96, @"设置执行权限");
    NSArray *bins = [fm contentsOfDirectoryAtPath:self.binDir error:NULL] ?: @[];
    NSUInteger fixed = 0;
    for (NSString *b in bins) {
        NSString *p = [self.binDir stringByAppendingPathComponent:b];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir) {
            [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:p error:NULL];
            fixed++;
        }
    }
    // helpers/ 必须可执行：里面是 bash（shell 本体）。
    // 少了执行位，posix_spawn 会拒绝启动，表现为「退出码 -1、耗时 0 秒」。
    NSString *helpers = [self.installRoot stringByAppendingPathComponent:@"helpers"];
    NSArray *helperBins = [fm contentsOfDirectoryAtPath:helpers error:NULL] ?: @[];
    for (NSString *b in helperBins) {
        NSString *p = [helpers stringByAppendingPathComponent:b];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir) {
            [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:p error:NULL];
        }
    }
    if (helperBins.count) SPLog(@"helpers 已 chmod 755：%lu 个（含 bash）", (unsigned long)helperBins.count);

    // 逆向工具与 ollvm 里的可执行文件
    for (NSString *d in @[self.reverseBinDir, [self.ollvmRoot stringByAppendingPathComponent:@"bin"]]) {
        for (NSString *b in [fm contentsOfDirectoryAtPath:d error:NULL] ?: @[]) {
            NSString *p = [d stringByAppendingPathComponent:b];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir) {
                [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:p error:NULL];
            }
        }
    }
    SPLog(@"工具链展开完成：bin %lu 个，已 chmod 755，复制失败 %lu 个",
          (unsigned long)fixed, (unsigned long)failedCopies);

    // 写标记前先验收：关键文件不全就不要说装好了。
    // 否则用户看到「已就绪」，编译时才发现缺 clang/ld64/logos.pl。
    NSMutableArray<NSString *> *missing = [NSMutableArray array];

    // 按实际探到的路径校验，不要写死 theos/ 前缀 ——
    // Rein 对齐包的 theos 本体在 theos-root/theos，
    // 写死会导致「装好了但判定为缺失」。
    NSString *theosDir = self.theosPath;
    for (NSString *rel in @[@"makefiles/common.mk", @"bin/logos.pl"]) {
        if (![fm fileExistsAtPath:[theosDir stringByAppendingPathComponent:rel]]) {
            [missing addObject:[NSString stringWithFormat:@"theos/%@", rel]];
        }
    }

    // 编译链逐个确认「存在且可执行」。
    // 只判存在不够：分包解压出来是 444（只读），没有执行位照样跑不起来，
    // 而且报错是 posix_spawn 失败（退出码 -1），完全看不出是权限问题。
    for (NSString *tool in @[@"clang-16", @"ld64", @"ldid", @"make", @"dpkg-deb", @"perl"]) {
        NSString *p = [self.binDir stringByAppendingPathComponent:tool];
        if (![fm isExecutableFileAtPath:p]) {
            p = [self.baseBinDir stringByAppendingPathComponent:tool];
        }
        if (![fm isExecutableFileAtPath:p]) {
            [missing addObject:[NSString stringWithFormat:@"%@（缺失或不可执行）", tool]];
        }
    }

    // shell 单独确认：它在 helpers/ 下，是子进程能否启动的关键
    {
        BOOL anyShell = NO;
        for (NSString *sh in @[@"bash", @"sh"]) {
            NSString *p = [dst stringByAppendingPathComponent:
                           [@"helpers" stringByAppendingPathComponent:sh]];
            if ([fm isExecutableFileAtPath:p]) { anyShell = YES; break; }
        }
        if (!anyShell) [missing addObject:@"helpers/bash（shell 不可执行）"];
    }

    // SDK：至少一个带 SDKSettings.json 的
    {
        BOOL anySDK = NO;
        for (NSString *rel in @[@"sdks", @"theos/sdks", @"theos-root/theos/sdks"]) {
            NSString *dir = [dst stringByAppendingPathComponent:rel];
            for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
                if (![name hasPrefix:@"iPhoneOS"] || ![name hasSuffix:@".sdk"]) continue;
                if ([fm fileExistsAtPath:[[dir stringByAppendingPathComponent:name]
                        stringByAppendingPathComponent:@"SDKSettings.json"]]) { anySDK = YES; break; }
            }
            if (anySDK) break;
        }
        if (!anySDK) [missing addObject:@"iPhoneOS*.sdk"];
    }

    if (missing.count) {
        // 清掉半成品，避免 isInstalled 误判
        [fm removeItemAtPath:dst error:NULL];
        return SPError(SPErrorCodeMissingToolchain,
            [NSString stringWithFormat:
             @"工具链解包不完整，缺少：%@\n\n"
              "请重新安装，或用「设置 → 工具链 → 重新展开」。",
             [missing componentsJoinedByString:@"、"]]);
    }

    // 落一个标记文件（isInstalled 用）
    NSString *stampText = [NSString stringWithFormat:@"installed at %@\n", [NSDate date]];
    [stampText writeToFile:[dst stringByAppendingPathComponent:@".installed"]
                atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    if (progress) progress(1.0, @"完成");
    return nil;
}

- (void)uninstall {
    [NSFileManager.defaultManager removeItemAtPath:self.installRoot error:NULL];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInstalledVersionKey];
}

@end
