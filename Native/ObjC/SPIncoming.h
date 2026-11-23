//
//  SPIncoming.h
//  Workbench —— 收件箱：把分享/导入进来的文件整理成「可直接用的东西」
//
//  来源：
//   · Share Extension 写进 App Group 的 Incoming/<job>/
//   · 用户在「设置 → 接收文件」导入的
//   · 文件 App 通过「用 Workbench 打开」传来的（openURL）
//
//  导入后的归类：
//   · 含 Makefile / control 的目录    → 可注册为项目
//   · *.deb / *.zip / *.ipa           → 包，可解包
//   · *.dylib / *.framework / *.bundle → 插件库（注入器直接可用）
//   · *.sdk 目录 / *SDK*.zip          → 工具链 SDK
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPIncomingKind) {
    SPIncomingKindProject = 0,   // 看起来是个工程
    SPIncomingKindPlugin,        // dylib / framework / bundle
    SPIncomingKindPackage,       // deb / zip / ipa
    SPIncomingKindSDK,           // SDK 目录或压缩包
    SPIncomingKindOther,
};

@interface SPIncomingItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) SPIncomingKind kind;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, copy) NSString *kindText;
@end

@interface SPIncoming : NSObject

+ (instancetype)shared;

/// Share Extension 用的共享容器（nil 表示没有 App Group 权限）
+ (nullable NSString *)sharedContainerPath;

/// 把 Share Extension 留下的 Incoming/<job>/ 搬进收件箱
- (NSArray<SPIncomingItem *> *)drainSharedIncoming;

/// 收件箱条目（按修改时间倒序）
- (NSArray<SPIncomingItem *> *)items;

/// 导入外部文件/目录（复制进收件箱并归类）
- (nullable SPIncomingItem *)importPath:(NSString *)path error:(NSError *_Nullable *_Nullable)error;

/// 把条目注册成项目（不是工程时返回 nil）
- (nullable NSString *)makeProjectFrom:(SPIncomingItem *)item error:(NSError *_Nullable *_Nullable)error;

- (void)remove:(SPIncomingItem *)item;
- (unsigned long long)totalSize;

@end

NS_ASSUME_NONNULL_END
