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
    // Resources/Toolchain 会被当成 folder reference 拷进 .app
    NSString *p = [[NSBundle mainBundle] pathForResource:@"Toolchain" ofType:nil];
    if (p) return p;
    p = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Toolchain"];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}

- (BOOL)hasBundledToolchain { return self.bundledRoot != nil; }

/// 运行时结构有三种来源，统一在这里判定：
///   A. CodexApp / 我们早期打的包：  usr/bin  + usr/lib  + theos/
///   B. Rein(DSH.app) 对齐包：       helpers/ + alpine-rootfs/ +
///                                   theos-root/usr/bin + sdks/
///   C. 最早期：                     bin/ + lib/ + theos/
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
    NSArray *cands = @[@"theos-full", @"theos", @"TheosRuntime/theos",
                       @"theos-root/theos", @"theos-min"];
    for (NSString *rel in cands) {
        NSString *p = [self.installRoot stringByAppendingPathComponent:rel];
        if (![fm fileExistsAtPath:[p stringByAppendingPathComponent:@"makefiles/common.mk"]]) continue;
        // 还要确认 sdks 里真的有 SDK
        NSString *sdks = [p stringByAppendingPathComponent:@"sdks"];
        BOOL hasSDK = NO;
        for (NSString *name in [fm contentsOfDirectoryAtPath:sdks error:NULL] ?: @[]) {
            if ([name hasPrefix:@"iPhoneOS"] && [name hasSuffix:@".sdk"]) { hasSDK = YES; break; }
        }
        if (hasSDK) return p;
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
    NSArray<NSString *> *required = @[
        @"theos/makefiles/common.mk",
        @"theos/bin/logos.pl",
    ];
    for (NSString *r in required) {
        if (![fm fileExistsAtPath:[dst stringByAppendingPathComponent:r]]) {
            [missing addObject:r];
        }
    }
    BOOL hasLinker = [fm isExecutableFileAtPath:[self.binDir stringByAppendingPathComponent:@"ld64"]];
    BOOL hasClang  = [fm isExecutableFileAtPath:[self.binDir stringByAppendingPathComponent:@"clang-16"]];
    if (!hasLinker && !hasClang) [missing addObject:@"bin/ld64 或 bin/clang-16"];

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
