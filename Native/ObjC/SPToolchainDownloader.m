//
//  SPToolchainDownloader.m
//

#import "SPToolchainDownloader.h"
#import "SPToolchainInstaller.h"
#import "SPCompat.h"
#import "SPSession.h"
#import "SPToolchain.h"

static NSString *const kComponentStateKey = @"Spark.components";
static NSString *const kDefaultBase = @"https://github.com/JiuJiuyu77/Spark/releases/download/toolchain-v1";

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
@end

@implementation SPToolchainDownloader

+ (instancetype)shared {
    static SPToolchainDownloader *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [SPToolchainDownloader new];
        d.baseURL = kDefaultBase;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60;
        cfg.timeoutIntervalForResource = 3600;
        d.session = [NSURLSession sessionWithConfiguration:cfg delegate:d delegateQueue:nil];
    });
    return d;
}

- (NSString *)directoryFor:(SPComponent)component {
    NSString *root = [SPToolchainInstaller shared].installRoot;
    switch (component) {
        case SPComponentOLLVM:    return [root stringByAppendingPathComponent:@"ollvm"];
        case SPComponentReverse:  return [root stringByAppendingPathComponent:@"reverse"];
        default:                  return [root stringByAppendingPathComponent:@"fulltools"];
    }
}

- (NSString *)fileNameFor:(SPComponent)component {
    switch (component) {
        case SPComponentOLLVM:   return @"ollvm.tar.gz";
        case SPComponentReverse: return @"reverse.tar.gz";
        default:                 return @"fulltools.tar.gz";
    }
}

- (NSArray<SPComponentInfo *> *)components {
    NSMutableArray *out = [NSMutableArray array];

    SPComponentInfo *ollvm = [SPComponentInfo new];
    ollvm.component = SPComponentOLLVM;
    ollvm.title = @"OLLVM 混淆编译器";
    ollvm.detail = @"Arkari LLVM 16，5 个混淆 pass";
    ollvm.symbol = @"wand.and.stars";
    ollvm.approxSize = 80ULL * 1024 * 1024;
    [out addObject:ollvm];

    SPComponentInfo *rev = [SPComponentInfo new];
    rev.component = SPComponentReverse;
    rev.title = @"逆向工具";
    rev.detail = @"radare2 / mt-macho / 注入 dylib";
    rev.symbol = @"binoculars.fill";
    rev.approxSize = 60ULL * 1024 * 1024;
    [out addObject:rev];

    SPComponentInfo *full = [SPComponentInfo new];
    full.component = SPComponentFullTools;
    full.title = @"完整工具集";
    full.detail = @"perl / python / 其余命令行工具";
    full.symbol = @"shippingbox.fill";
    full.approxSize = 40ULL * 1024 * 1024;
    [out addObject:full];

    return out;
}

- (void)reload { /* 状态是懒判断的，这里只是占位 */ }

#pragma mark - 下载

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

    NSString *urlStr = [NSString stringWithFormat:@"%@/%@", self.baseURL, [self fileNameFor:component]];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, SPError(SPErrorCodeIO, @"下载地址无效"));
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"Spark/1.2" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.session downloadTaskWithRequest:req];
    [self.task resume];
    if (progress) progress(0, @"连接中…");
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *dir = self.destinationDir;
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

    // 解包：优先用内置 tar
    NSString *tar = [SPUtil findExecutable:@[@"tar"] searchDirs:@[
        [SPToolchainInstaller shared].binDir, @"/usr/bin", @"/var/jb/usr/bin", @"/bin"]];
    BOOL ok = NO;
    if (tar) {
        NSString *cmd = [NSString stringWithFormat:@"%@ xzf %@ -C %@ --strip-components=1 2>/dev/null || %@ xzf %@ -C %@",
                         [SPUtil shellQuote:tar], [SPUtil shellQuote:location.path],
                         [SPUtil shellQuote:dir],
                         [SPUtil shellQuote:tar], [SPUtil shellQuote:location.path],
                         [SPUtil shellQuote:dir]];
        SPCommandResult *r = [SPSession runSyncShell:cmd environment:@{} cwd:NSTemporaryDirectory() timeout:300];
        ok = r.exitCode == 0;
    }
    if (ok) {
        // bin 下补执行权限
        for (NSString *sub in @[@"bin", @"reverse/bin"]) {
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
        if (self.completionBlock) self.completionBlock(ok, ok ? nil : SPError(SPErrorCodeIO, @"解包失败，请检查下载包"));
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
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock) {
            self.progressBlock(f, [NSString stringWithFormat:@"%@ / %@",
                                   [SPUtil formatBytes:(unsigned long long)totalBytesWritten],
                                   [SPUtil formatBytes:(unsigned long long)totalBytesExpectedToWrite]]);
        }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionBlock) self.completionBlock(NO, error);
        self.task = nil;
        self.progressBlock = nil;
        self.completionBlock = nil;
    });
}

- (void)remove:(SPComponent)component {
    [[NSFileManager defaultManager] removeItemAtPath:[self directoryFor:component] error:NULL];
    [[SPToolchain shared] rescan];
}

@end
