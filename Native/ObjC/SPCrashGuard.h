//
//  SPCrashGuard.h
//  Workbench —— 崩溃兜底
//
//  目标不是「吞掉崩溃」，而是：
//   1. 未捕获的 NSException 先落盘（谁抛的、调用栈、当时在做哪类操作）
//   2. 最常见的几类异常现场「救回来」（例如容器类插入 nil）
//   3. 下次启动时提示「上次崩了，要看报告吗」
//
//  Signal 崩溃（SIGSEGV 等）无法安全恢复，只记录信息供排查。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPCrashGuard : NSObject

+ (instancetype)shared;

/// 在 App 启动最早期调用
- (void)install;

/// 给当前操作打标签（例如 "build:MyTweak"），崩溃报告里会带上
- (void)setContext:(NSString *)context;

/// 上次是否异常退出，若有返回报告路径
- (nullable NSString *)pendingReportPath;

/// 清掉「待查看」标记
- (void)consumePendingReport;

/// 所有历史报告（按时间倒序）
- (NSArray<NSString *> *)reportPaths;

@end

NS_ASSUME_NONNULL_END
