//
//  SPAppEnumerator.h
//  Workbench —— App 枚举（B1：走 LaunchServices，拿到真实图标与显示名）
//
//  为什么不用文件系统枚举：
//   · /Applications 与 /var/containers/Bundle/Application 只能列出「装在哪」，
//     拿不到用户重命名过的显示名，也拿不到系统缓存的图标
//   · LaunchServices 的 LSApplicationProxy 才是 App 的真实来源
//     （TrollFools / TrollStore 都用它）
//
//  LSApplicationWorkspace 是私有 API，版本差异大，所以做成两层：
//   1. 动态调用 LSApplicationWorkspace（NSClassFromString + performSelector，
//      不引私有头文件，编译期不会报错）
//   2. 拿不到就回退文件系统枚举（一定有结果，只是没图标缓存）
//
//  这样 Workbench 不必在编译期链接私有框架。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *executable;
@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, copy, nullable) NSString *dataContainer;
@property (nonatomic, assign) BOOL isSystem;
@property (nonatomic, assign) BOOL isFromLaunchServices;
@end

@interface SPAppEnumerator : NSObject

+ (instancetype)shared;

/// 枚举所有已安装 App（优先 LaunchServices，失败回退文件系统）
- (NSArray<SPAppInfo *> *)allApps;

/// 按 bundleId 找单个 App
- (nullable SPAppInfo *)appWithBundleId:(NSString *)bundleId;

/// 取图标（LaunchServices 有缓存；回退到读 .app 里的 png）
- (nullable UIImage *)iconForBundleId:(NSString *)bundleId size:(CGFloat)size;

/// 本次枚举是否走了 LaunchServices
@property (nonatomic, readonly) BOOL usedLaunchServices;

/// 最近一次枚举耗时
@property (nonatomic, readonly) NSTimeInterval lastEnumerationSeconds;

@end

NS_ASSUME_NONNULL_END
