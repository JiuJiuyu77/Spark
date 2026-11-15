//
//  SPInstall.h
//  Spark —— 产物一键安装（TrollStore / dpkg）
//
//  这是巨魔环境独有的能力（自签 App 做不到）：
//   · 编出来的 deb 直接 dpkg -i 装到本机
//   · 改好的 .app 交给 TrollStore 覆盖安装
//   · 装完可以卸载（dpkg -r）
//
//  安全设计：
//   · 每个操作先 dry-run 打印将要做的事，用户确认才执行
//   · 安装前记录包名，便于回滚
//   · 所有命令都以 root 跑（TrollStore 环境 getuid() == 0）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPInstallKind) {
    SPInstallKindDeb = 0,     // dpkg -i
    SPInstallKindApp,         // 交给 TrollStore
    SPInstallKindDylib,       // 拷到 MobileSubstrate 插件目录
};

@interface SPInstallTask : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) SPInstallKind kind;
@property (nonatomic, copy) NSString *title;        // 显示名（包名或 App 名）
@property (nonatomic, copy, nullable) NSString *packageId;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, assign) BOOL installed;       // 当前是否已装
@end

@interface SPInstall : NSObject

+ (instancetype)shared;

/// 分析一个产物，判断该用哪种安装方式
- (nullable SPInstallTask *)inspectPath:(NSString *)path error:(NSError *_Nullable *_Nullable)error;

/// 安装（返回执行日志）
- (void)installTask:(SPInstallTask *)task
         completion:(void (^)(BOOL ok, NSString *log))completion;

/// 卸载某个包
- (void)uninstallPackageId:(NSString *)packageId
                completion:(void (^)(BOOL ok, NSString *log))completion;

/// 列出本机已装的 Spark 相关包（文件名匹配 given 前缀）
- (NSArray<NSString *> *)installedPackageIds;

@end

NS_ASSUME_NONNULL_END
