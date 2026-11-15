//
//  SPPrivileged.h
//  Spark —— 以 root 身份运行子进程（巨魔/TrollStore 特有）
//
//  背景：
//   · Dylix 那种自签 App 只能在沙盒里想办法，进程永远是自己那个 uid
//   · 巨魔 App 有 platform-application + no-sandbox，**可以**降到 root 跑子进程
//     —— TrollStore 会显示「应用可以以 root 权限执行其内置的二进制文件」
//   · 这正是 Rein 显示「root 权限执行内置二进制」的原因
//
//  实现要点：
//   1. 用 posix_spawnattr_setpersona_np 或 fork 后 setuid(0) 降权/提权
//   2. 必须先检查 getuid()，非 0 时不要盲目 setuid（会失败）
//   3. 记录每次提权结果，设置页可查看
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPPrivileged : NSObject

+ (instancetype)shared;

/// 当前进程 uid（0 = root）
@property (nonatomic, readonly) uid_t currentUID;

/// 是否有能力把子进程提到 root
@property (nonatomic, readonly) BOOL canElevate;

/// 提交结果说明（设置页展示）
@property (nonatomic, readonly) NSString *statusText;

/// 启动时调用：尝试把自己切到 root（有 platform-application 时通常直接成功）
/// 返回是否真的成了 root
- (BOOL)elevateSelf;

/// 探活：起一个 `id` 看实际 uid/gid
- (void)probeWithCompletion:(void (^)(NSString *detail))completion;

/// 以 root 身份执行一段 shell（失败时回退到当前身份）
/// @param script 命令
/// @param completion 主线程回调：输出 + 是否真的 root
- (void)runAsRoot:(NSString *)script
       completion:(void (^)(BOOL ok, BOOL wasRoot, NSString *output))completion;

@end

NS_ASSUME_NONNULL_END
