//
//  RBBuilder.h
//  ReinBuild —— 构建编排：把「项目 + 选项 + 工具链」变成一条可执行的 shell 脚本，
//  逐行收日志，结束后收集产物（deb / app / dylib），并做签名与体积统计。
//

#import <Foundation/Foundation.h>
#import "RBModels.h"
#import "RBToolchain.h"
#import "RBSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface RBBuilder : NSObject

/// 生成要交给 /bin/sh -c 的完整脚本（纯函数，方便单元测试与「预览命令」）
+ (NSString *)scriptForProject:(RBProject *)project
                       options:(RBBuildOptions *)options
                       profile:(RBToolchainProfile *)profile
                    backupPath:(nullable NSString *)backupPath;

/// 从 make 输出里解析 prerm/postinst 之类路径不安全，这里只做「产物目录扫描」
+ (NSArray<NSString *> *)collectArtifactsInProject:(NSString *)projectPath
                                           since:(NSDate *)since
                                          options:(RBBuildOptions *)options;

/// 从日志尾部推断失败原因，返回一句人话；无法判断返回 nil
+ (nullable NSString *)diagnoseFailureFromLines:(NSArray<RBLogLine *> *)lines;

/// 一键构建。onLine 逐行回调，completion 在主线程回调。
+ (RBSession *)buildProject:(RBProject *)project
                    options:(RBBuildOptions *)options
                    profile:(RBToolchainProfile *)profile
                   onLine:(nullable void (^)(NSString *line, RBLogLevel level))onLine
                 onFinish:(void (^)(RBJob *job))onFinish;

/// 取消指针（对应 RBSession）
+ (void)cancelSession:(RBSession *)session;

@end

NS_ASSUME_NONNULL_END
