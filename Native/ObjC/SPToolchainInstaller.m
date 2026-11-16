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
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark/Toolchain"];
}

- (NSString *)bundledRoot {
    // Resources/Toolchain 会被当成 folder reference 拷进 .app
    NSString *p = [[NSBundle mainBundle] pathForResource:@"Toolchain" ofType:nil];
    if (p) return p;
    p = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Toolchain"];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}

- (BOOL)hasBundledToolchain { return self.bundledRoot != nil; }

- (NSString *)binDir {
    // CodexApp 结构：usr/bin；旧版结构：bin/。优先 usr/bin（编译链都在那里）
    NSString *usr = [self.installRoot stringByAppendingPathComponent:@"usr/bin"];
    if ([NSFileManager.defaultManager fileExistsAtPath:usr]) return usr;
    return [self.installRoot stringByAppendingPathComponent:@"bin"];
}
- (NSString *)libDir {
    NSString *usr = [self.installRoot stringByAppendingPathComponent:@"usr/lib"];
    if ([NSFileManager.defaultManager fileExistsAtPath:usr]) return usr;
    return [self.installRoot stringByAppendingPathComponent:@"lib"];
}
- (NSString *)theosPath     { return [self.installRoot stringByAppendingPathComponent:@"theos"]; }
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
    NSString *stamp = [self.installRoot stringByAppendingPathComponent:@".installed"];
    if (![fm fileExistsAtPath:stamp]) return NO;
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
