//
//  RBToolchain.h
//  ReinBuild —— 工具链发现与构建环境组装。
//
//  行为完全对齐 Rein：按「用户设置 → 安装目录 → 设备上的 Rein 目录」优先级探测，
//  找到什么就用什么，找不到的来源在 UI 里标红并给出修复建议。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RBToolchainComponent) {
    RBToolchainComponentTheos = 0,   // make + makefiles + Logos
    RBToolchainComponentSDK,         // iPhoneOS*.sdk
    RBToolchainComponentDarwin,      // clang/ld64/ldid/strip/ar（真机可执行）
    RBToolchainComponentOLLVM,       // Arkari LLVM 混淆编译器
    RBToolchainComponentReverse,     // radare2 / mt-macho / mt-inject-dylib
    RBToolchainComponentPython,      // python3
    RBToolchainComponentNode,        // node / pnpm
    RBToolchainComponentDevices,     // ssh/scp（远程编译）
    RBToolchainComponentCount
};

/// 远端/本地编译目标
typedef NS_ENUM(NSInteger, RBBuildTarget) {
    RBBuildTargetDevice = 0,   // 在本机直接跑 make（Rein 里的「真机编译」）
    RBBuildTargetRemote,       // 通过 ssh 在另一台越狱设备上 make
    RBBuildTargetCI,           // 推到 GitHub 走 Actions
};

/// 一份「实际生效的」工具链路径集合。字段都可能为 nil，用 usable 判断。
@interface RBToolchainProfile : NSObject

@property (nonatomic, copy) NSString *name;                 // "本机" / "远程 iPhone" / "GitHub CI"
@property (nonatomic, assign) RBBuildTarget target;

@property (nonatomic, copy, nullable) NSString *theosPath;      // THEOS
@property (nonatomic, copy, nullable) NSString *sdkPath;        // 选中的 SDK 绝对路径
@property (nonatomic, copy) NSString *sdkName;                  // "iPhoneOS16.5.sdk"
@property (nonatomic, copy, nullable) NSString *darwinBinDir;   // clang/ld64/ldid 目录
@property (nonatomic, copy, nullable) NSString *ollvmRoot;      // OLLVM 根（含 bin/clang）
@property (nonatomic, copy, nullable) NSString *reverseBinDir;  // radare2 等目录
@property (nonatomic, copy, nullable) NSString *python3;
@property (nonatomic, copy, nullable) NSString *node;
@property (nonatomic, copy, nullable) NSString *sshHost;        // 远程
@property (nonatomic, copy, nullable) NSString *sshUser;
@property (nonatomic, assign) NSInteger sshPort;

/// 生成传给 make / 子进程的环境变量（不含 PATH 拼接，PATH 由 RBSession 另算）
- (NSDictionary<NSString *, NSString *> *)extraEnvironment;

@end

#pragma mark - 工具链扫描结果

@interface RBToolchainScan : NSObject
/// 每个组件是否找到
- (BOOL)has:(RBToolchainComponent)c;
/// 某个组件对应的人类可读路径（找不到时给空字符串）
- (NSString *)pathFor:(RBToolchainComponent)c;
/// 简短状态描述，例如 "Theos ✓  iPhoneOS17.0.sdk ✓  OLLVM ✗"
- (NSString *)summary;
/// 缺失组件的修复建议
- (NSArray<NSString *> *)remedies;
@end

@interface RBToolchain : NSObject

/// 单例，扫描是懒加载 + 可刷新
+ (instancetype)shared;

/// 探测根目录（按优先级）：用户设置的安装目录、Rein 目录、App 包内
@property (nonatomic, copy) NSString *reinRoot;      // 默认 /var/mobile/Documents/Rein
@property (nonatomic, copy, nullable) NSString *homeRoot; // 用户自定义安装目录

- (void)rescan;
@property (nonatomic, readonly) RBToolchainScan *scan;

/// 可用 SDK 名列表（"iPhoneOS16.5.sdk" ...）
- (NSArray<NSString *> *)availableSDKs;

/// 组装本机 profile。sdkName 为 nil 时择优；失败返回 nil 并填充 error。
- (nullable RBToolchainProfile *)localProfileWithSDK:(nullable NSString *)sdkName
                                              error:(NSError *_Nullable *_Nullable)error;

/// 远程 profile（只有 ssh 配置，用于远程构建）
- (RBToolchainProfile *)remoteProfileWithHost:(NSString *)host
                                         user:(NSString *)user
                                         port:(NSInteger)port
                                          sdk:(nullable NSString *)sdkName;

/// CI profile：命令在 macOS runner 上执行，本地只负责打包上传
- (RBToolchainProfile *)ciProfileWithSDK:(nullable NSString *)sdkName;

/// 直接把 PATH 前缀（Darwin bin + theos bin + 系统目录）拼出来
- (NSString *)pathPrefixForProfile:(RBToolchainProfile *)profile;

@end

NS_ASSUME_NONNULL_END
