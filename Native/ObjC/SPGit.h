//
//  SPGit.h
//  Spark —— 轻量 Git 面板（参考 Dylix 的 GitService）
//
//  只调用系统 git（CoreTools 运行时里带了 git 2.39），不引 libgit2：
//   · 巨魔环境本来就允许 fork 子进程，用 git 命令行最简单可靠
//   · 支持：状态 / 暂存 / 提交 / 差异 / 历史 / 初始化 / 远端 / 推送
//
//  凭据：token 存 Keychain，通过 credential helper 临时注入，不写进 .git/config
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPGitFileStatus : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *status;      // M / A / D / R / ??
@property (nonatomic, assign) BOOL staged;
@property (nonatomic, assign) BOOL untracked;
@end

@interface SPGitCommit : NSObject
@property (nonatomic, copy) NSString *hash;
@property (nonatomic, copy) NSString *shortHash;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *date;
@property (nonatomic, copy) NSString *message;
@end

@interface SPGit : NSObject

+ (instancetype)shared;
+ (dispatch_queue_t)queue;      // 所有 git 操作都在这条串行队列上跑

@property (nonatomic, readonly, nullable) NSString *gitPath;

/// 仓库状态；不是仓库返回 nil 并给 error
- (nullable NSDictionary *)statusAtRoot:(NSString *)root error:(NSError *_Nullable *_Nullable)error;

/// 是否已经是 git 仓库
- (BOOL)isRepository:(NSString *)root;

/// git init
- (BOOL)initializeRoot:(NSString *)root error:(NSError *_Nullable *_Nullable)error;

/// 暂存 / 取消暂存
- (BOOL)stagePaths:(NSArray<NSString *> *)paths root:(NSString *)root error:(NSError *_Nullable *_Nullable)error;
- (BOOL)unstagePaths:(NSArray<NSString *> *)paths root:(NSString *)root error:(NSError *_Nullable *_Nullable)error;

/// 提交（返回新提交的短 hash）
- (nullable NSString *)commitRoot:(NSString *)root
                          message:(NSString *)message
                             name:(NSString *)name
                            email:(NSString *)email
                            error:(NSError *_Nullable *_Nullable)error;

/// 某文件的 diff（不传 path 就是全部）
- (nullable NSString *)diffRoot:(NSString *)root path:(nullable NSString *)path staged:(BOOL)staged;

/// 最近若干条提交
- (NSArray<SPGitCommit *> *)historyRoot:(NSString *)root limit:(NSInteger)limit;

/// 设置远端
- (BOOL)setRemoteRoot:(NSString *)root url:(NSString *)url error:(NSError *_Nullable *_Nullable)error;

/// 推送（token 走环境变量，不落盘）
- (nullable NSString *)pushRoot:(NSString *)root
                          remote:(NSString *)remote
                          branch:(NSString *)branch
                          token:(nullable NSString *)token
                          error:(NSError *_Nullable *_Nullable)error;

/// 当前分支名
- (nullable NSString *)currentBranchRoot:(NSString *)root;

@end

NS_ASSUME_NONNULL_END
