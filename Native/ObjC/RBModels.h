//
//  RBModels.h
//  ReinBuild —— 项目、构建选项、任务、日志的模型层。
//  全部可 JSON 序列化，便于「最近项目」「构建历史」「远程/CI 传输」。
//

#import <Foundation/Foundation.h>
#import "RBToolchain.h"

NS_ASSUME_NONNULL_BEGIN

/// 项目类型（由 Makefile/目录结构探测得出）
typedef NS_ENUM(NSInteger, RBProjectKind) {
    RBProjectKindUnknown = 0,
    RBProjectKindTweak,       // THEOS_PACKAGE_SCHEME / tweak
    RBProjectKindApplication, // application
    RBProjectKindLibrary,     // library
    RBProjectKindTool,        // tool
    RBProjectKindBundle,      // bundle
    RBProjectKindNode,        // package.json
    RBProjectKindScript,      // 只有 build 脚本
};

/// 打包格式
typedef NS_ENUM(NSInteger, RBPackageFormat) {
    RBPackageFormatDeb = 0,
    RBPackageFormatRootlessDeb,  // THEOS_PACKAGE_SCHEME = rootless
    RBPackageFormatApp,          // 不打包，直接产出 .app
    RBPackageFormatTIPA,
};

/// 架构
typedef NS_ENUM(NSInteger, RBArch) {
    RBArchArm64 = 0,
    RBArchArm64e,
    RBArchBoth,
};

/// OLLVM 混淆等级（对应 Rein 的 passes 组合）
typedef NS_ENUM(NSInteger, RBObfuscation) {
    RBObfuscationNone = 0,
    RBObfuscationLight,     // indbr + cse
    RBObfuscationBalanced,  // indbr + icall + cse
    RBObfuscationStrong,    // 全部 5 个 pass
    RBObfuscationCustom,    // 自定义 passes
};

#pragma mark - 构建选项

@interface RBBuildOptions : NSObject <NSCopying>

@property (nonatomic, assign) RBArch arch;
@property (nonatomic, assign) RBPackageFormat format;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, assign) BOOL cleanBeforeBuild;
@property (nonatomic, assign) BOOL finalize;      // 打包并生成 deb
@property (nonatomic, assign) BOOL signWithLdid;
@property (nonatomic, assign) BOOL strip;
@property (nonatomic, assign) BOOL useOLLVM;
@property (nonatomic, assign) RBObfuscation obfuscation;
@property (nonatomic, copy) NSArray<NSString *> *obfuscationPasses; // 自定义时生效
@property (nonatomic, copy, nullable) NSString *packageVersionOverride;
@property (nonatomic, copy, nullable) NSString *extraMakeArgs;      // 原样拼在 make 后面
@property (nonatomic, copy, nullable) NSString *extraEnv;           // "K=V\nK2=V2"
@property (nonatomic, assign) BOOL parallel;                        // -jN
@property (nonatomic, assign) NSInteger jobs;

- (NSArray<NSString *> *)makeArguments;
- (NSDictionary<NSString *, NSString *> *)makeEnvironment;
- (NSString *)displaySummary;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)optionsFromDictionary:(NSDictionary *)dict;

@end

#pragma mark - 项目

@interface RBProject : NSObject

@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RBProjectKind kind;
@property (nonatomic, copy, nullable) NSString *packageId;      // com.example.foo
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *executable;     // 主二进制名
@property (nonatomic, copy, nullable) NSString *makefilePath;
@property (nonatomic, copy) NSArray<NSString *> *sourceFiles;   // 相对路径
@property (nonatomic, copy) NSArray<NSString *> *headers;
@property (nonatomic, copy, nullable) NSString *buildDir;       // ".theos"
@property (nonatomic, copy, nullable) NSString *layoutDir;      // "layout"
@property (nonatomic, assign) BOOL isTheosProject;
@property (nonatomic, copy) RBBuildOptions *options;
@property (nonatomic, strong) NSDate *lastOpenedAt;

+ (nullable instancetype)projectAtPath:(NSString *)path error:(NSError *_Nullable *_Nullable)error;
- (void)reload;
- (NSArray<NSString *> *)fileTreeFlattened;   // 供文件浏览使用
- (NSString *)kindString;

@end

#pragma mark - 日志

typedef NS_ENUM(NSInteger, RBLogLevel) {
    RBLogLevelOut = 0,
    RBLogLevelErr,
    RBLogLevelInfo,
    RBLogLevelStep,
};

@interface RBLogLine : NSObject
@property (nonatomic, strong) NSDate *time;
@property (nonatomic, assign) RBLogLevel level;
@property (nonatomic, copy) NSString *text;
+ (instancetype)lineWithText:(NSString *)text level:(RBLogLevel)level;
@end

#pragma mark - 任务

typedef NS_ENUM(NSInteger, RBJobState) {
    RBJobStateQueued = 0,
    RBJobStateRunning,
    RBJobStateSucceeded,
    RBJobStateFailed,
    RBJobStateCancelled,
};

@interface RBJob : NSObject

@property (nonatomic, copy) NSString *jobId;
@property (nonatomic, copy) NSString *projectPath;
@property (nonatomic, copy) NSString *projectName;
@property (nonatomic, strong) RBBuildOptions *options;
@property (nonatomic, assign) RBBuildTarget target;
@property (nonatomic, assign) RBJobState state;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSDate *finishedAt;
@property (nonatomic, assign) NSInteger exitCode;
@property (nonatomic, copy) NSArray<RBLogLine *> *lines;
@property (nonatomic, copy) NSArray<NSString *> *artifacts;       // 产出的文件绝对路径
@property (nonatomic, copy, nullable) NSString *bundlePath;       // .deb 或 .app
@property (nonatomic, copy, nullable) NSString *failureHint;      // 从日志推断的错误说明

- (NSTimeInterval)duration;
- (NSString *)stateString;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
