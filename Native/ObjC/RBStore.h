//
//  RBStore.h
//  ReinBuild —— 本地持久化（JSON 文件，放在 Documents/ReinBuild 下）
//

#import <Foundation/Foundation.h>
#import "RBModels.h"
#import "RBToolchain.h"

NS_ASSUME_NONNULL_BEGIN

/// 全局设置
@interface RBSettings : NSObject <NSCopying>

@property (nonatomic, copy) NSString *projectsRoot;        // 默认 Documents/ReinBuild/projects
@property (nonatomic, copy) NSString *defaultSDK;
@property (nonatomic, assign) RBBuildTarget defaultTarget;
@property (nonatomic, copy, nullable) NSString *sshHost;
@property (nonatomic, copy, nullable) NSString *sshUser;
@property (nonatomic, assign) NSInteger sshPort;
@property (nonatomic, copy, nullable) NSString *sshKeyPath;
@property (nonatomic, copy, nullable) NSString *githubRepo;   // owner/name
@property (nonatomic, copy, nullable) NSString *githubBranch;
@property (nonatomic, assign) BOOL keepScreenOn;
@property (nonatomic, assign) BOOL hapticsOnBuildDone;
@property (nonatomic, assign) NSInteger maxLogLines;
@property (nonatomic, assign) BOOL showCommandPreview;

@property (nonatomic, copy, nullable) NSString *sshPassword; // 存于 Keychain，此处仅内存使用

+ (instancetype)shared;
- (void)save;

@end

/// 最近项目 / 构建历史 / 工具链扫描缓存
@interface RBStore : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSString *baseDirectory;

/// 最近打开的项目（RBProject 的最小快照，路径 + 选项 + 时间）
- (NSArray<NSDictionary *> *)recentProjects;
- (void)pushRecentProject:(RBProject *)project;
- (void)removeRecentProjectAtPath:(NSString *)path;

/// 构建历史（按时间倒序，最多保留 N 条）
- (NSArray<NSDictionary *> *)buildHistory;
- (void)appendBuildRecord:(RBJob *)job;

/// 每个项目的选项持久化：<base>/options/<hash>.json
- (RBBuildOptions *)optionsForProjectPath:(NSString *)path;
- (void)saveOptions:(RBBuildOptions *)options forProjectPath:(NSString *)path;

/// 常用路径
- (NSString *)projectsDirectory;
- (NSString *)artifactsDirectory;
- (NSString *)logsDirectory;
- (NSString *)archivesDirectory;

/// 把字符串写进日志文件，返回路径
- (nullable NSString *)persistLogText:(NSString *)text jobId:(NSString *)jobId;

@end

NS_ASSUME_NONNULL_END
