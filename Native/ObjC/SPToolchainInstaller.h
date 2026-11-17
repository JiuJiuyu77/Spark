//
//  SPToolchainInstaller.h
//  Spark —— 内置工具链的首启安装器
//
//  ipa 里带着 Resources/Toolchain（约 480MB，含 clang/ld64/ldid/Theos/OLLVM/radare2）。
//  首次启动时解到 Documents/Spark/Toolchain 并 chmod +x，
//  之后所有构建都直接用这份 —— 不再依赖设备上是否装了 Rein。
//
//  SDK 不内置（Apple 的东西不适合再分发），由用户在「设置 → SDK」里导入压缩包。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SPToolchainInstaller;

typedef void (^SPInstallProgress)(CGFloat fraction, NSString *status);
typedef void (^SPInstallCompletion)(BOOL ok, NSError *_Nullable error);

@interface SPToolchainInstaller : NSObject

+ (instancetype)shared;

/// 安装根目录：Documents/Spark/Toolchain
@property (nonatomic, readonly) NSString *installRoot;

/// 包内工具链目录（[[NSBundle mainBundle] pathForResource:@"Toolchain" ofType:nil]）
@property (nonatomic, readonly, nullable) NSString *bundledRoot;

/// 是否已安装且完整
@property (nonatomic, readonly, getter=isInstalled) BOOL installed;

/// 已安装版本（包内 manifest 里的 builtAt），用于判断是否需要重新展开
@property (nonatomic, readonly, nullable) NSString *installedVersion;

/// 是否正在安装
@property (nonatomic, readonly, getter=isInstalling) BOOL installing;

/// 包内是否带了工具链（CI 没塞进来时为 NO）
@property (nonatomic, readonly) BOOL hasBundledToolchain;

/// 执行安装（后台队列，回调在主线程）。已安装且版本一致时立即返回成功。
- (void)installWithProgress:(nullable SPInstallProgress)progress
                 completion:(SPInstallCompletion)completion;

/// 强制作废并重装
- (void)reinstallWithProgress:(nullable SPInstallProgress)progress
                   completion:(SPInstallCompletion)completion;

/// 卸载（释放空间）
- (void)uninstall;

/// 直接给出各组件路径（安装后可用）
@property (nonatomic, readonly) NSString *binDir;       // usr/bin（优先）或 bin
@property (nonatomic, readonly) NSString *baseBinDir;   // 始终是 bin（基础命令）
@property (nonatomic, readonly) NSString *perl5Dir;
/// Rein 结构：Linux 容器启动器与 rootfs（不存在时返回路径但不保证可用）
@property (nonatomic, readonly) NSString *ishdPath;
@property (nonatomic, readonly) NSString *alpineRoot;
/// 是否具备完整 Linux 运行时（ishd + alpine-rootfs）
@property (nonatomic, readonly) BOOL hasLinuxRuntime;     // lib/perl5
@property (nonatomic, readonly) NSString *libDir;       // usr/lib（优先）或 lib
@property (nonatomic, readonly) NSString *theosPath;    // Toolchain/theos
@property (nonatomic, readonly) NSString *ollvmRoot;    // Toolchain/ollvm
@property (nonatomic, readonly) NSString *reverseBinDir;// Toolchain/reverse/bin

@end

NS_ASSUME_NONNULL_END
