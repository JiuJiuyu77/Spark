//
//  SPCrashAnalysis.h
//  Workbench —— 离线崩溃分析（解析 iOS .ips 报告）
//
//  能做的事（不需要 Mac、不需要符号文件）：
//   · 解析 JSON 格式的 .ips（iOS 15+）与老式文本 .crash
//   · 提取异常类型、信号、终止原因、触发线程
//   · 还原调用栈（把 frame 的 imageIndex 映射回二进制名）
//   · 常见崩溃模式识别：野指针 / 栈溢出 / 死锁 / KVO / 数组越界 /
//     主线程 I/O / 内存不足 / 未捕获 ObjC 异常
//   · 若崩溃 App 是我们的工程，标出落在哪个源文件（有 dSYM 时更准）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPCrashSeverity) {
    SPCrashSeverityInfo = 0,
    SPCrashSeverityWarn,
    SPCrashSeverityError,
};

@interface SPCrashFrame : NSObject
@property (nonatomic, copy) NSString *image;      // 二进制名
@property (nonatomic, copy) NSString *symbol;     // 符号（可能为空）
@property (nonatomic, assign) unsigned long long offset;
@end

@interface SPCrashFinding : NSObject
@property (nonatomic, assign) SPCrashSeverity severity;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy, nullable) NSString *suggestion;
@end

@interface SPCrashReport : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *osVersion;
@property (nonatomic, copy) NSString *device;
@property (nonatomic, strong, nullable) NSDate *crashTime;
@property (nonatomic, copy) NSString *exceptionType;   // EXC_BAD_ACCESS 等
@property (nonatomic, copy) NSString *signal;          // SIGSEGV 等
@property (nonatomic, copy) NSString *termination;     // 终止原因
@property (nonatomic, copy) NSString *triggeredThread; // 触发线程名
@property (nonatomic, copy) NSArray<SPCrashFrame *> *frames;
@property (nonatomic, copy) NSArray<SPCrashFinding *> *findings;
/// 一句话结论
@property (nonatomic, copy) NSString *summary;
/// 生成的完整可读报告
@property (nonatomic, copy) NSString *plainText;
@end

@interface SPCrashAnalysis : NSObject

/// 解析一个 .ips / .crash 文件
+ (nullable SPCrashReport *)analyzePath:(NSString *)path error:(NSError *_Nullable *_Nullable)error;

/// 扫描常见崩溃目录，返回所有报告（按时间倒序）
+ (NSArray<SPCrashReport *> *)scanCommonDirectories;

/// 把报告导出成 markdown（便于分享）
+ (NSString *)markdownForReport:(SPCrashReport *)report;

@end

NS_ASSUME_NONNULL_END
