//
//  SPToolchainDownloader.m  (重写：改为由 ProjectKit/src/runtimes.mjs 的数据驱动)
//

#import "SPToolchainDownloader.h"
#import "SPToolchain.h"
#import "SPToolchainInstaller.h"
#import "SPSession.h"
#import "SPCompat.h"

static NSString *const kComponentStateKey = @"Spark.downloadedComponents";

/**
 * 运行时清单（与 ProjectKit/src/runtimes.mjs 保持一致）。
 * 之所以在 ObjC 里再写一份：iOS 运行时不一定有 node，
 * 但两份的 id / 体积 / 探测命令必须一致，改的时候一起改。
 */
static NSArray<NSDictionary *> *SPRuntimeManifest(void) {
    static NSArray *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 与 ProjectKit/src/runtimes.mjs 一致；选型见 docs/runtime-decision.md
        NSString *codex = @"https://github.com/susu123oss/CodexApp-Runtime/releases/download";
        NSString *self_ = @"https://github.com/JiuJiuyu77/Spark-Runtime/releases/download/runtime-v1";
        m = @[
          @{@"id": @"coretools", @"name": @"核心工具集", @"size": @(10*1024*1024), @"order": @5,
            @"archive": [codex stringByAppendingString:@"/runtime-core-tools-a7e97567217a/CoreToolsRuntime.tar.gz"],
            @"probe": @"bin/git", @"detail": @"git / curl / jq / rg / zip", @"symbol": @"terminal.fill"},
          @{@"id": @"reverse", @"name": @"逆向工具", @"size": @(17*1024*1024), @"order": @10,
            @"archive": [codex stringByAppendingString:@"/runtime-reverse-tools-9d3ca9ea3340/ReverseToolsRuntime.tar.gz"],
            @"probe": @"bin/rabin2", @"detail": @"radare2 / mt-macho / 注入 dylib", @"symbol": @"binoculars.fill"},
          @{@"id": @"node", @"name": @"Node.js 24.5.0", @"size": @(28*1024*1024), @"order": @15,
            @"archive": [codex stringByAppendingString:@"/runtime-node-24.5.0-e3a6c25fac33/NodeRuntime.tar.gz"],
            @"probe": @"bin/node", @"detail": @"24.5.0 + npm 11.5 + node-gyp iOS 适配", @"symbol": @"curlybraces"},
          @{@"id": @"buildtools", @"name": @"构建工具", @"size": @(8*1024*1024), @"order": @15,
            @"archive": [codex stringByAppendingString:@"/runtime-build-tools-3.27.9-fb0f29cea7b2/BuildToolsRuntime.tar.gz"],
            @"probe": @"bin/ninja", @"detail": @"CMake 3.27.9 + Ninja 1.11.1", @"symbol": @"hammer.fill"},
          @{@"id": @"python", @"name": @"Python 3.13", @"size": @(10*1024*1024), @"order": @20,
            @"archive": [codex stringByAppendingString:@"/runtime-python-3.13.14-3c834a2c8964/PythonRuntime.tar.gz"],
            @"probe": @"bin/python3", @"detail": @"Python 3.13.14", @"symbol": @"chevron.left.forwardslash.chevron.right"},
          @{@"id": @"theos", @"name": @"Theos 完整版", @"size": @(114*1024*1024), @"order": @25,
            @"archive": [self_ stringByAppendingString:@"/SparkTheosRuntime.tar.gz"],
            @"probe": @"theos/bin/logos.pl", @"detail": @"含 16.5 / 17.0 两个 SDK", @"symbol": @"wrench.and.screwdriver.fill"},
          @{@"id": @"ollvm", @"name": @"OLLVM 混淆", @"size": @(35*1024*1024), @"order": @30,
            @"archive": [codex stringByAppendingString:@"/runtime-ollvm-23.1.1-e54f2878240e/OLLVMRuntime.tar.gz"],
            @"probe": @"bin/clang", @"detail": @"LLVM 23.1.1，7 个 pass", @"symbol": @"wand.and.stars"},
        ];
    });
    return m;
}

/// 直连失败时用的镜像前缀
static NSArray<NSString *> *SPProxyPrefixes(void) {
    return @[@"", @"https://gh-proxy.org/", @"https://ghproxy.net/"];
}

@implementation SPComponentInfo
- (BOOL)isInstalled {
    NSString *dir = [[SPToolchainDownloader shared] directoryFor:self.component];
    return [[NSFileManager defaultManager] fileExistsAtPath:
            [dir stringByAppendingPathComponent:@".installed"]];
}
@end

@interface SPToolchainDownloader () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, copy) void (^progressBlock)(CGFloat, NSString *);
@property (nonatomic, copy) void (^completionBlock)(BOOL, NSError *);
@property (nonatomic, assign) SPComponent currentComponent;
@property (nonatomic, strong) NSString *destinationDir;
@property (nonatomic, assign) NSInteger proxyIndex;
@end

@implementation SPToolchainDownloader

+ (instancetype)shared {
    static SPToolchainDownloader *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [SPToolchainDownloader new];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60;
        cfg.timeoutIntervalForResource = 7200;
        d.session = [NSURLSession sessionWithConfiguration:cfg delegate:d delegateQueue:nil];
    });
    return d;
}

/// 组件 → 安装子目录（与 runtimes.mjs 的 id 对齐）
- (NSString *)directoryFor:(SPComponent)component {
    NSArray *m = SPRuntimeManifest();
    NSString *root = [SPToolchainInstaller shared].installRoot;
    if (component >= 0 && component < (NSInteger)m.count) {
        return [root stringByAppendingPathComponent:m[component][@"id"]];
    }
    return root;
}

- (NSArray<SPComponentInfo *> *)components {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *m = SPRuntimeManifest();
    for (NSInteger i = 0; i < (NSInteger)m.count; i++) {
        NSDictionary *d = m[i];
        SPComponentInfo *c = [SPComponentInfo new];
        c.component = i;
        c.title = d[@"name"];
        c.detail = d[@"detail"];
        c.symbol = d[@"symbol"];
        c.approxSize = [d[@"size"] unsignedLongLongValue];
        [out addObject:c];
    }
    return out;
}

- (void)reload { /* 状态懒判断 */ }

#pragma mark - 下载

- (void)startTaskForCurrentComponent {
    NSArray *m = SPRuntimeManifest();
    NSInteger i = self.currentComponent;
    if (i < 0 || i >= (NSInteger)m.count) {
        if (self.completionBlock) self.completionBlock(NO, SPError(SPErrorCodeIO, @"未知组件"));
        return;
    }
    NSString *url = m[i][@"archive"];
    NSArray *prefixes = SPProxyPrefixes();
    if (self.proxyIndex >= (NSInteger)prefixes.count) {
        if (self.completionBlock) self.completionBlock(NO, SPError(SPErrorCodeIO, @"所有下载源都失败，请检查网络"));
        self.task = nil;
        return;
    }
    NSString *prefix = prefixes[self.proxyIndex];
    NSString *finalURL = [prefix stringByAppendingString:url];
    if (self.progressBlock) {
        NSString *via = prefix.length ? [NSString stringWithFormat:@"（镜像 %@）", prefix] : @"（直连）";
        self.progressBlock(0.02, [NSString stringWithFormat:@"连接中%@", via]);
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:finalURL]];
    [req setValue:@"Spark/1.3" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.session downloadTaskWithRequest:req];
    [self.task resume];
}

- (void)download:(SPComponent)component
        progress:(void (^)(CGFloat, NSString *))progress
      completion:(void (^)(BOOL, NSError *))completion {
    if (self.task) {
        if (completion) completion(NO, SPError(SPErrorCodeIO, @"已有下载在进行"));
        return;
    }
    self.currentComponent = component;
    self.progressBlock = progress;
    self.completionBlock = completion;
    self.destinationDir = [self directoryFor:component];
    self.proxyIndex = 0;
    [[NSFileManager defaultManager] createDirectoryAtPath:self.destinationDir
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [self startTaskForCurrentComponent];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = self.destinationDir;

    // 用内置 tar 解包（core_tools 没装时退回系统 tar）
    NSString *tar = [SPUtil findExecutable:@[@"tar"] searchDirs:@[
        [SPToolchainInstaller shared].binDir,
        [SPToolchainInstaller shared].installRoot,
        @"/usr/bin", @"/var/jb/usr/bin", @"/bin"]];
    BOOL ok = NO;
    if (tar) {
        if (self.progressBlock) dispatch_async(dispatch_get_main_queue(), ^{ self.progressBlock(0.95, @"解包…"); });
        NSString *cmd = [NSString stringWithFormat:
            @"%@ xzf %@ -C %@ 2>/dev/null || %@ xzf %@ -C %@ --strip-components=1 2>/dev/null",
            [SPUtil shellQuote:tar], [SPUtil shellQuote:location.path], [SPUtil shellQuote:dir],
            [SPUtil shellQuote:tar], [SPUtil shellQuote:location.path], [SPUtil shellQuote:dir]];
        SPCommandResult *r = [SPSession runSyncShell:cmd environment:@{} cwd:NSTemporaryDirectory() timeout:600];
        ok = (r.exitCode == 0);
    }
    if (ok) {
        // 补执行权限
        for (NSString *sub in @[@"bin", @"sbin", @"libexec"]) {
            NSString *d = [dir stringByAppendingPathComponent:sub];
            for (NSString *f in [fm contentsOfDirectoryAtPath:d error:NULL] ?: @[]) {
                [fm setAttributes:@{NSFilePosixPermissions: @(0755)}
               ofItemAtPath:[d stringByAppendingPathComponent:f] error:NULL];
            }
        }
        [@"ok" writeToFile:[dir stringByAppendingPathComponent:@".installed"]
                atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock) self.progressBlock(1.0, ok ? @"完成" : @"解包失败");
        if (self.completionBlock) self.completionBlock(ok, ok ? nil : SPError(SPErrorCodeIO, @"解包失败"));
        self.task = nil;
        self.progressBlock = nil;
        self.completionBlock = nil;
        [[SPToolchain shared] rescan];
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0) return;
    CGFloat f = (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite;
    NSString *text = [NSString stringWithFormat:@"%@ / %@",
                      [SPUtil formatBytes:(unsigned long long)totalBytesWritten],
                      [SPUtil formatBytes:(unsigned long long)totalBytesExpectedToWrite]];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock) self.progressBlock(MAX(0.02, f * 0.93), text);
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) return;
    // 直连失败 → 换镜像重试
    dispatch_async(dispatch_get_main_queue(), ^{
        self.proxyIndex += 1;
        self.task = nil;
        if (self.proxyIndex < (NSInteger)SPProxyPrefixes().count) {
            [self startTaskForCurrentComponent];
            return;
        }
        if (self.completionBlock) self.completionBlock(NO, error);
        self.progressBlock = nil;
        self.completionBlock = nil;
    });
}

- (void)remove:(SPComponent)component {
    [[NSFileManager defaultManager] removeItemAtPath:[self directoryFor:component] error:NULL];
    [[SPToolchain shared] rescan];
}

@end
