//
//  SPBackground.h
//  Spark —— 后台保活（编译/注入这类长任务不能因为切后台被杀）
//
//  手段（从稳到弱）：
//   1. 静音音频循环播放 —— 声明 UIBackgroundModes=audio，切后台后仍能跑
//   2. beginBackgroundTask —— 系统给的约 30 秒，用于「收尾保存」
//   3. 两者叠加：音频撑住主体，backgroundTask 兜住退出瞬间
//
//  注意：
//   · 音频只在「有长任务在跑」时开启，任务结束立刻释放（省电、也不占音频焦点）
//   · 尊重用户的「后台保活」开关，默认开
//   · 不假装能永久保活：iOS 仍可能因系统压力挂起，这里只尽量延长
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPBackground : NSObject

+ (instancetype)shared;

/// 用户开关（设置 → 显示与反馈 → 后台保活）
@property (nonatomic, assign) BOOL userEnabled;

/// 当前是否在保活
@property (nonatomic, readonly, getter=isActive) BOOL active;

/// 当前有几个任务申请了保活
@property (nonatomic, readonly) NSInteger activeTaskCount;

/// 申请保活（可重入，计数归零才真正停）
- (void)beginKeepAlive:(NSString *)reason;

/// 结束保活
- (void)endKeepAlive:(NSString *)reason;

/// 兜底的后台任务（进入后台时申请，退出后台时结束）
- (void)beginBackgroundTask;
- (void)endBackgroundTask;

/// 状态说明（设置页展示）
@property (nonatomic, readonly) NSString *statusText;

/// 最近一次因为切后台被系统挂起的时间（nil 表示没有）
@property (nonatomic, readonly, strong, nullable) NSDate *lastSuspendedAt;

@end

NS_ASSUME_NONNULL_END
