//
//  SPHealthCheck.h
//  Workbench —— 统一健康检查（运行时 / 编译链 / 工具链 / 环境）
//
//  为什么重做
//  ----------
//  之前「测试构建」把环境、工具链、Theos、SDK 混在一条流水线上，
//  失败时只能看到「第 N 步没过」，看不到：
//    · 到底执行了什么命令
//    · 命令的原始输出是什么
//    · 这个报错用人话讲是什么意思
//  排查仍然要靠猜。
//
//  现在拆成四个独立的类别，每项检查都记录：
//    command   —— 实际跑的 shell 命令（可复制到终端复现）
//    output    —— 原始输出（截断保护，避免几十 MB 日志撑爆内存）
//    diagnosis —— 失败时的人话解释 + 下一步怎么办
//
//  检查之间**互不阻塞**：环境不通也照样跑编译链检查，
//  这样一次就能看到全部问题，而不是修一个跑一次。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPHealthCategory) {
    SPHealthCategoryRuntime = 0,   // 运行时：shell、临时目录、helpers、磁盘
    SPHealthCategoryCompiler,      // 编译链：clang / ld64 / ldid / strip / ar
    SPHealthCategoryToolchain,     // 工具链：Theos makefiles / logos / vendor / SDK
    SPHealthCategoryEnvironment,   // 环境：身份、权限、PATH、架构
    SPHealthCategoryCount
};

typedef NS_ENUM(NSInteger, SPHealthStatus) {
    SPHealthStatusPending = 0,
    SPHealthStatusRunning,
    SPHealthStatusPass,
    SPHealthStatusWarn,     // 能用，但有隐患
    SPHealthStatusFail,
    SPHealthStatusSkip,     // 前置条件不满足，跳过
};

@interface SPHealthItem : NSObject

@property (nonatomic, assign) SPHealthCategory category;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) SPHealthStatus status;

/// 一句话结论（通过时也可以有，比如「clang 16.0.6」）
@property (nonatomic, copy, nullable) NSString *summary;

/// 实际执行的 shell 命令，便于用户复制到终端复现。
/// 纯文件检查（不跑命令）时为 nil。
@property (nonatomic, copy, nullable) NSString *command;

/// 命令的原始输出（已截断）
@property (nonatomic, copy, nullable) NSString *output;

/// 退出码（跑了命令才有意义）
@property (nonatomic, assign) NSInteger exitCode;

/// 失败/警告时的人话解释与下一步
@property (nonatomic, copy, nullable) NSString *diagnosis;

/// 耗时的毫秒数
@property (nonatomic, assign) NSInteger elapsedMS;

@property (nonatomic, readonly) BOOL isFailure;
@end

@interface SPHealthReport : NSObject
@property (nonatomic, strong) NSArray<SPHealthItem *> *items;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, assign) NSTimeInterval totalSeconds;

- (NSInteger)countForStatus:(SPHealthStatus)status;
- (NSInteger)countForCategory:(SPHealthCategory)category;
- (NSArray<SPHealthItem *> *)itemsInCategory:(SPHealthCategory)category;
/// 总体结论：有任何 Fail → NO
@property (nonatomic, readonly) BOOL allPassed;
/// 给人看的一句话总结
- (NSString *)headline;
@end

@interface SPHealthCheck : NSObject

+ (NSString *)titleForCategory:(SPHealthCategory)category;
+ (NSString *)symbolForCategory:(SPHealthCategory)category;

/// 逐项回调（主线程）。全部跑完后 completion 给出完整报告。
/// 每个类别内部顺序执行，类别之间也顺序执行（避免同时起一堆子进程）。
- (void)runWithItemUpdate:(void (^)(SPHealthItem *item))itemUpdate
               completion:(void (^)(SPHealthReport *report))completion;

/// 只跑指定类别（nil = 全部）
- (void)runCategories:(nullable NSArray<NSNumber *> *)categories
           itemUpdate:(void (^)(SPHealthItem *item))itemUpdate
           completion:(void (^)(SPHealthReport *report))completion;

@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// 把一段 shell 输出翻译成人话。失败诊断统一走这里。
+ (nullable NSString *)humanizeOutput:(NSString *)output
                             exitCode:(NSInteger)exitCode
                               intent:(nullable NSString *)intent;

@end

NS_ASSUME_NONNULL_END