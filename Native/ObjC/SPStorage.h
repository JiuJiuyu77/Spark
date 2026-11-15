//
//  SPStorage.h
//  Spark —— 存储空间管理（参考 Dylix 的 StorageSpace 设计思路）
//
//  目标：让用户清楚看到「谁占了空间」，并且能分门别类地清理。
//  分类固定为这几类，扫描根目录显式传入（便于测试与模拟）：
//   · projects   工程源码（.theos / packages 可以清）
//   · artifacts  产物与归档
//   · logs       日志
//   · inbox      收件箱
//   · toolchain  工具链（含可选组件）
//   · caches     临时与构建缓存
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPStorageCategory) {
    SPStorageCategoryProjects = 0,
    SPStorageCategoryArtifacts,
    SPStorageCategoryLogs,
    SPStorageCategoryInbox,
    SPStorageCategoryToolchain,
    SPStorageCategoryCaches,
    SPStorageCategoryCount,
};

@interface SPStorageEntry : NSObject
@property (nonatomic, assign) SPStorageCategory category;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) unsigned long long bytes;
@property (nonatomic, assign) NSUInteger fileCount;
/// 可以安全清理的部分（例如工程里的 .theos/packages 子目录）
@property (nonatomic, assign) unsigned long long cleanableBytes;
@end

@interface SPStorage : NSObject

+ (instancetype)shared;

/// 扫描（会比较慢，放后台）
- (NSArray<SPStorageEntry *> *)scan;

/// 清理某一类里「可清理」的部分，返回释放的字节数
- (unsigned long long)cleanCategory:(SPStorageCategory)category error:(NSError *_Nullable *_Nullable)error;

/// 清理工程里的构建中间产物（.theos/obj / packages），保留源码
- (unsigned long long)cleanProjectCachesKeeping:(nullable NSString *)keepProjectPath
                                          error:(NSError *_Nullable *_Nullable)error;

/// 磁盘总容量与可用空间
- (NSDictionary<NSString *, NSNumber *> *)diskSpace;

@end

NS_ASSUME_NONNULL_END
