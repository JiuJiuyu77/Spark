//
//  SPLinuxRuntime.m
//

#import "SPLinuxRuntime.h"
#import "SPCompat.h"
#import "SPPrivileged.h"
#import "SPToolchainInstaller.h"
#import "SPSession.h"

@interface SPLinuxRuntime ()
@property (nonatomic, assign) SPLinuxRuntimeState state;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, strong, nullable) SPSession *container;
@property (nonatomic, copy, nullable) NSString *runningRootfs;
@end

@implementation SPLinuxRuntime

+ (instancetype)shared {
    static SPLinuxRuntime *r;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        r = [SPLinuxRuntime new];
        r.state = SPLinuxRuntimeStateUnavailable;
        r.statusText = @"未探测";
    });
    return r;
}

#pragma mark - 探测

- (void)probeWithCompletion:(void (^)(SPLinuxRuntimeState, NSString *))completion {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];

    NSString *ishd = inst.ishdPath;
    NSString *rootfs = inst.alpineRoot;
    NSFileManager *fm = NSFileManager.defaultManager;

    // ① 组件是否存在
    if (![fm fileExistsAtPath:ishd] || ![fm fileExistsAtPath:rootfs]) {
        self.state = SPLinuxRuntimeStateUnavailable;
        self.statusText = @"缺少 ishd 或 alpine-rootfs：\n"
                          @"当前工具链不是 Rein 对齐结构。\n"
                          @"请导入 SparkReinRuntime.tar.gz。";
        if (completion) completion(self.state, self.statusText);
        return;
    }

    // ② ishd 必须是可执行的 Mach-O
    if (![fm isExecutableFileAtPath:ishd]) {
        self.state = SPLinuxRuntimeStateUnavailable;
        self.statusText = @"ishd 没有可执行权限";
        if (completion) completion(self.state, self.statusText);
        return;
    }

    // ③ rootfs 结构检查：必须有 /bin 或 /usr/bin
    BOOL hasBin = [fm fileExistsAtPath:[rootfs stringByAppendingPathComponent:@"data/bin"]]
               || [fm fileExistsAtPath:[rootfs stringByAppendingPathComponent:@"data/usr/bin"]]
               || [fm fileExistsAtPath:[rootfs stringByAppendingPathComponent:@"bin"]];
    if (!hasBin) {
        self.state = SPLinuxRuntimeStateUnavailable;
        self.statusText = @"alpine-rootfs 结构异常（找不到 bin 目录）";
        if (completion) completion(self.state, self.statusText);
        return;
    }

    // ④ 必须 root：chroot / bind mount 都需要
    //    注意判据是**当前进程**，子进程身份由构建脚本单独确认。
    if (getuid() != 0 && ![[SPPrivileged shared] ensureRoot]) {
        self.state = SPLinuxRuntimeStateNotRoot;
        self.statusText = [NSString stringWithFormat:
            @"有 ishd 与 rootfs，但当前不是 root（uid=%d）。\n"
             "Linux 容器需要 chroot 权限 —— 请用 TrollStore 安装 Spark。",
            (int)getuid()];
        if (completion) completion(self.state, self.statusText);
        return;
    }

    self.state = SPLinuxRuntimeStateReady;
    self.statusText = [NSString stringWithFormat:@"可以启动（rootfs：%@）",
                       rootfs.lastPathComponent];
    if (completion) completion(self.state, self.statusText);
}

#pragma mark - 启动

- (void)startWithRootfs:(NSString *)rootfsPath
             completion:(void (^)(BOOL, NSError *, NSString *))completion {
    if (self.container.isRunning) {
        if (completion) completion(YES, nil, @"容器已在运行");
        return;
    }

    NSString *ishd = [SPToolchainInstaller shared].ishdPath;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm isExecutableFileAtPath:ishd]) {
        NSError *e = SPError(SPErrorCodeMissingToolchain,
            @"找不到可执行的 ishd：当前工具链不是 Rein 对齐结构。\n"
             "请在「设置 → 工具链」里导入 SparkReinRuntime.tar.gz。");
        if (completion) completion(NO, e, @"");
        return;
    }

    // alpine-rootfs 必须可写（ishd 要 mount_root / 应用 RootfsPatch）。
    // 包内是只读的，这里按需复制一份到 Documents —— 只有 8MB，很快；
    // 511MB 的 theos-root 依然直接用包内路径，不复制。
    rootfsPath = [self prepareWritableRootfs:rootfsPath];

    // chroot 必须有 root
    if (getuid() != 0 && ![[SPPrivileged shared] ensureRoot]) {
        NSError *e = SPError(SPErrorCodeLaunchFailed,
            [NSString stringWithFormat:
             @"Linux 容器需要 root（当前 uid=%d）。\n"
              "Spark 必须通过 TrollStore 安装（platform-application 权限）。",
             (int)getuid()]);
        if (completion) completion(NO, e, @"");
        return;
    }

    // ishd 的 rootfs 参数是**包含 data/ 的那一层**：
    // Rein 的布局是 alpine-rootfs/{data,meta.db}，
    // ishd 自己会拼 data 路径（字符串里有 "rootfs canonical data path"）。
    SPSession *s = [[SPSession alloc] initWithEnvironment:@{}
                                          workingDirectory:NSTemporaryDirectory()];
    s.timeout = 60;

    NSMutableArray *lines = [NSMutableArray array];
    s.onLine = ^(NSString *line, SPLogLevel lv) {
        if (line.length) @synchronized (lines) { [lines addObject:line]; }
    };

    __weak typeof(self) weakSelf = self;
    s.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *joined = nil;
        @synchronized (lines) { joined = [lines componentsJoinedByString:@"\n"]; }

        // ishd 启动成功会在输出里出现这两句之一
        BOOL booted = [joined containsString:@"Root filesystem mounted"]
                   || [joined containsString:@"Already booted"]
                   || [joined containsString:@"become_first_process"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (booted) {
                self.state = SPLinuxRuntimeStateRunning;
                self.runningRootfs = rootfsPath;
                self.statusText = @"容器已启动";
                if (completion) completion(YES, nil, joined);
            } else {
                NSError *e = SPError(SPErrorCodeLaunchFailed,
                    [NSString stringWithFormat:
                     @"容器启动失败（exit %ld）。\n\n%@",
                     (long)r.exitCode,
                     joined.length > 800 ? [joined substringFromIndex:joined.length - 800] : joined]);
                if (completion) completion(NO, e, joined);
            }
        });
    };

    self.container = s;
    NSString *cmd = [NSString stringWithFormat:@"%@ --root %@",
                     [SPUtil shellQuote:ishd],
                     [SPUtil shellQuote:rootfsPath]];
    SPLog(@"启动 Linux 容器：%@", cmd);
    [s runShell:cmd];
}

/// 把（可能只读的）rootfs 准备到可写位置。
/// 已经在 Documents 里就直接返回；在 App 包里就复制一份。
- (NSString *)prepareWritableRootfs:(NSString *)rootfs {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *writable = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark"]
                          stringByAppendingPathComponent:@"alpine-rootfs"];

    // 已经是可写位置
    if ([rootfs hasPrefix:NSHomeDirectory()]) return rootfs;

    // 已经复制过（且比包内的新）
    if ([fm fileExistsAtPath:writable]) {
        SPLog(@"复用已准备好的 rootfs：%@", writable);
        return writable;
    }

    SPLog(@"首次准备 rootfs（复制 %@）", rootfs.lastPathComponent);
    [fm removeItemAtPath:writable error:NULL];
    [fm createDirectoryAtPath:[writable stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES attributes:nil error:NULL];

    NSError *err = nil;
    if (![fm copyItemAtPath:rootfs toPath:writable error:&err]) {
        SPLog(@"[!] 复制 rootfs 失败：%@", err.localizedDescription);
        // 复制失败时退回原路径（可能只读，容器大概率起不来，
        // 但至少让 startWithRootfs 报出真实的错误而不是这里静默失败）
        return rootfs;
    }
    return writable;
}

#pragma mark - 执行

- (void)runInContainer:(NSString *)script
                rootfs:(NSString *)rootfsPath
            completion:(void (^)(BOOL, NSString *))completion {
    // 容器没起来先启动
    if (!self.container.isRunning) {
        [self startWithRootfs:rootfsPath completion:^(BOOL ok, NSError *e, NSString *log) {
            if (!ok) {
                if (completion) completion(NO, e.localizedDescription ?: log);
                return;
            }
            [self runInContainer:script rootfs:rootfsPath completion:completion];
        }];
        return;
    }

    // 容器已在运行：在容器里执行。
    // ishd 提供 exec 子命令；路径映射靠它自己的 /dsh bind mount。
    NSString *ishd = [SPToolchainInstaller shared].ishdPath;
    NSString *cmd = [NSString stringWithFormat:@"%@ exec -- %@",
                     [SPUtil shellQuote:ishd],
                     [SPUtil shellQuote:script]];

    SPSession *s = [[SPSession alloc] initWithEnvironment:@{}
                                          workingDirectory:NSTemporaryDirectory()];
    s.timeout = 600;
    __block NSString *out = @"";
    s.onLine = ^(NSString *line, SPLogLevel lv) {
        out = [out stringByAppendingFormat:@"%@\n", line ?: @""];
    };
    s.onFinish = ^(SPCommandResult *r) {
        NSString *text = r.stdoutText.length ? r.stdoutText : out;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(r.exitCode == 0, text ?: @"");
        });
    };
    [s runShell:cmd];
}

- (void)stop {
    [self.container cancel];
    self.container = nil;
    self.runningRootfs = nil;
    self.state = SPLinuxRuntimeStateReady;
    self.statusText = @"已停止";
}

@end
