//
//  SPCrashGuard.m
//

#import "SPCrashGuard.h"
#import "SPCompat.h"
#import <UIKit/UIKit.h>
#import <signal.h>
#import <stdio.h>
#import <time.h>
#import <execinfo.h>

static NSString *const kContextKey = @"Spark.currentContext";
static NSString *const kCrashedFlag = @"Spark.crashedLastRun";

// 前置声明：install 方法里要用，定义在文件末尾
#include <exception>
static void SPHandleUncaughtException(NSException *exception);
// libdispatch / UIKit 内部抛的 C++ 异常最终走到 std::terminate
static void SPHandleCXXTerminate(void);
static void SPHandleSignal(int sig);

static NSString *SPCrashDirectory(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark/crashes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

/// 用纯 C 写文件：崩溃处理时不能依赖 Objective-C 运行时
static void SPWriteCrashFile(const char *name, const char *text) {
    NSString *dir = SPCrashDirectory();
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithUTF8String:name]];
    FILE *f = fopen(path.fileSystemRepresentation, "w");
    if (!f) return;
    fputs(text, f);
    fclose(f);
}

@implementation SPCrashGuard

+ (instancetype)shared {
    static SPCrashGuard *g; static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [SPCrashGuard new]; });
    return g;
}

#pragma mark - 安装

- (void)install {
    // 1. Objective-C 未捕获异常
    NSSetUncaughtExceptionHandler(&SPHandleUncaughtException);

    // 1b. 把「向容器插 nil」这类崩溃转成可读日志（它常表现为 _copyDescription 转发失败）
    NSSetUncaughtExceptionHandler(&SPHandleUncaughtException);

    // 1c. C++ 异常兜底（主队列 block 里抛的 C++ 异常会走 std::terminate）
    std::set_terminate(&SPHandleCXXTerminate);

    // 2. 致命信号：只记录，不尝试恢复（恢复会导致未定义行为）
    int signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP };
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
        signal(signals[i], SPHandleSignal);
    }

    // 3. 起点标记：能正常走到「进入后台/退出」就说明这次没崩
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kCrashedFlag];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setContext:(NSString *)context {
    [[NSUserDefaults standardUserDefaults] setObject:context ?: @"" forKey:kContextKey];
}

#pragma mark - 报告

- (NSArray<NSString *> *)reportPaths {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = SPCrashDirectory();
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
        if ([name hasSuffix:@".log"] || [name hasSuffix:@".txt"]) {
            [out addObject:[dir stringByAppendingPathComponent:name]];
        }
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];   // 文件名带时间戳
    }];
}

- (NSString *)pendingReportPath {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kCrashedFlag]) return nil;
    return [self reportPaths].firstObject;
}

- (void)consumePendingReport {
    // 只清标记，报告文件保留给用户查看
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kCrashedFlag];
}

@end

#pragma mark - C 处理函数

/// 把调用栈转成文本（最多 64 帧）
static void SPDumpBacktrace(char *buffer, size_t size) {
    void *frames[64];
    int n = backtrace(frames, 64);
    char **symbols = backtrace_symbols(frames, n);
    size_t used = 0;
    for (int i = 0; i < n && used < size - 1; i++) {
        int written = snprintf(buffer + used, size - used, "%s\n", symbols ? symbols[i] : "?");
        if (written <= 0) break;
        used += (size_t)written;
    }
    if (symbols) free(symbols);
}

static void SPHandleUncaughtException(NSException *exception) {
    @autoreleasepool {
        NSMutableString *report = [NSMutableString string];
        [report appendFormat:@"=== Spark 未捕获异常 ===\n"];
        [report appendFormat:@"时间: %@\n", [NSDate date]];
        [report appendFormat:@"名称: %@\n", exception.name];
        [report appendFormat:@"原因: %@\n", exception.reason];
        [report appendFormat:@"操作上下文: %@\n",
            [[NSUserDefaults standardUserDefaults] stringForKey:kContextKey] ?: @"（未设置）"];
        // 常见根因归因：NSInvalidArgumentException + _copyDescription 通常是给容器/属性塞了不该有的对象
        NSString *reason = exception.reason ?: @"";
        if ([reason containsString:@"_copyDescription"] ||
            [reason containsString:@"unrecognized selector"]) {
            [report appendString:@"疑似根因: 给 copy 属性或容器塞入了非预期类型（常见是 nil 走了 copy）\n"];
        }
        if ([reason containsString:@"NSInvalidArgumentException"] && [reason containsString:@"nil"]) {
            [report appendString:@"疑似根因: 向容器插入 nil\n"];
        }
        [report appendFormat:@"调用栈:\n%@\n", [exception.callStackSymbols componentsJoinedByString:@"\n"]];

        char bt[8192] = {0};
        SPDumpBacktrace(bt, sizeof(bt));
        [report appendFormat:@"backtrace:\n%s\n", bt];

        NSString *name = [NSString stringWithFormat:@"exception-%@.log", [SPUtil timestampSlug]];
        [report writeToFile:[SPCrashDirectory() stringByAppendingPathComponent:name]
                 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        SPLog(@"已保存崩溃报告 %@", name);
    }
}

static void SPHandleSignal(int sig) {
    char bt[8192] = {0};
    SPDumpBacktrace(bt, sizeof(bt));
    char text[9216];
    NSString *ctx = [[NSUserDefaults standardUserDefaults] stringForKey:kContextKey] ?: @"（未设置）";
    snprintf(text, sizeof(text), "=== Spark 信号崩溃 ===\n信号: %d\n操作上下文: %s\nbacktrace:\n%s\n",
             sig, [ctx UTF8String], bt);
    char name[64];
    time_t now = time(NULL);
    struct tm tmv;
    localtime_r(&now, &tmv);
    strftime(name, sizeof(name), "signal-%Y%m%d-%H%M%S.log", &tmv);
    SPWriteCrashFile(name, text);
    signal(sig, SIG_DFL);
    raise(sig);
}

#pragma mark - C++ terminate 兜底

static void SPHandleCXXTerminate(void) {
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"=== Spark C++ 异常终止（std::terminate）===\n"];
    [report appendFormat:@"时间: %@\n", [NSDate date]];

    NSString *ctx = [[NSUserDefaults standardUserDefaults] stringForKey:kContextKey];
    [report appendFormat:@"操作上下文: %@\n\n", ctx.length ? ctx : @"（未设置）"];

    [report appendString:@"当前线程调用栈:\n"];
    [report appendString:[NSThread callStackSymbols].componentsJoinedByString:@"\n"];

    char name[64];
    time_t now = time(NULL);
    struct tm tmv;
    localtime_r(&now, &tmv);
    strftime(name, sizeof(name), "cxx-terminate-%Y%m%d-%H%M%S.log", &tmv);
    SPWriteCrashFile(name, report);

    abort();
}
