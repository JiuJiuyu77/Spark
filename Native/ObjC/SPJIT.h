//
//  SPJIT.h
//  Spark —— JIT 加速
//
//  两条路，按设备能力自动挑：
//   1. 越狱/TrollStore 设备：调用 jetsam / JIT 相关 entitlement 已是平台级，
//      直接 mmap(PROT_EXEC) 就能分配可执行内存（不需要额外处理）
//   2. 普通签名的设备：需要 W^X 例外 —— 给可执行页打上
//      CS_DEBUGGED（attach 后自动具备），或使用 JIT 授权
//
//  本模块做的事：
//   · 启动时探测「JIT 是否可用」并记到设置里
//   · 提供一个可复用的可执行内存池（给需要 JIT 的场景，如正则/脚本引擎）
//   · UI 上显示当前 JIT 状态（设置 → 显示与反馈 → JIT 加速）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPJIT : NSObject

+ (instancetype)shared;

/// 当前是否具备 JIT 能力
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

/// 上次探测时间
@property (nonatomic, readonly, strong, nullable) NSDate *lastProbe;

/// 探测结果的一句话说明
@property (nonatomic, readonly) NSString *statusText;

/// 是否在 TrollStore / 越狱环境（有平台权限）
@property (nonatomic, readonly) BOOL isPlatformApp;

/// 主动探测（会实际申请一小块可执行内存再释放）
- (void)probe;

/// 申请一块可执行内存（失败返回 NULL）
- (nullable void *)allocateExecutable:(size_t)size;

/// 释放
- (void)freeExecutable:(void *)ptr size:(size_t)size;

/// 打开/关闭「JIT 加速」开关（关闭后只用解释执行，用于排查崩溃）
@property (nonatomic, assign) BOOL userEnabled;

@end

NS_ASSUME_NONNULL_END
