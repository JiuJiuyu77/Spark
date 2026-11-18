//
//  SPLinuxRuntime.h
//  Spark —— Linux 容器运行时（对齐 Rein 的 ishd + alpine-rootfs）
//
//  为什么需要
//  ---------
//  Spark 之前只有 darwin 工具链（theos-root），编译靠 clang-16 + ld64。
//  但 Rein 的做法是「ishd 起 Alpine 容器，在容器里跑 make」，
//  这条路径不依赖 darwin 二进制，也不受 iOS 沙盒对 fork/exec 的限制。
//
//  ishd 的行为（从二进制字符串还原）：
//    ishd --root <alpine-rootfs>
//      → [RootfsPatch] 应用增量补丁
//      → ISHKernel: mount_root / Root filesystem mounted at ...
//      → become_first_process 进入容器
//      → bindMount /dsh → 宿主目录（把项目目录映射进容器）
//
//  前置条件
//  --------
//  · 必须 root（chroot / bind mount 都需要）
//  · 必须能创建 unix socket（ish.sock）
//  · alpine-rootfs 已应用 RootfsPatch
//
//  没有满足条件时，本类不会假装能用 —— 会明确返回失败原因。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPLinuxRuntimeState) {
    SPLinuxRuntimeStateUnavailable = 0,  // 缺 ishd 或 rootfs
    SPLinuxRuntimeStateNotRoot,          // 有组件但没权限
    SPLinuxRuntimeStateReady,            // 可以启动
    SPLinuxRuntimeStateRunning,          // 容器已起来
};

@interface SPLinuxRuntime : NSObject

+ (instancetype)shared;

/// 当前状态（同步，读缓存）
@property (nonatomic, readonly) SPLinuxRuntimeState state;

/// 说明文字（设置页 / 自检展示）
@property (nonatomic, readonly) NSString *statusText;

/// 重新探测可用性（会检查 ishd 存在、rootfs 完整、是否 root）
- (void)probeWithCompletion:(void (^)(SPLinuxRuntimeState state, NSString *detail))completion;

/// 启动容器。
/// @param rootfsPath alpine-rootfs 路径（一般取自工具链安装目录）
/// @param completion 成功时返回容器已就绪
- (void)startWithRootfs:(NSString *)rootfsPath
             completion:(void (^)(BOOL ok, NSError *_Nullable error, NSString *log))completion;

/// 在容器里执行一段命令（容器未启动会自动先启动）
- (void)runInContainer:(NSString *)script
                 rootfs:(NSString *)rootfsPath
             completion:(void (^)(BOOL ok, NSString *output))completion;

/// 停止容器
- (void)stop;

@end

NS_ASSUME_NONNULL_END
