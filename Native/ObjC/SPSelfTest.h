//
//  SPSelfTest.h
//  Spark —— 测试构建（参考 Rein 的自检思路）
//
//  为什么需要
//  ---------
//  「构建失败」这个反馈太粗。可能的原因至少有七类：
//    ① 工具链没装/没展开        ② 不是 root
//    ③ SDK 缺失                 ④ Theos makefiles 找不到
//    ⑤ 子进程起不来             ⑥ 磁盘/权限不足
//    ⑦ 工程本身有问题
//  用户拿到的只有 make 的几百行输出，无从下手。
//
//  做法：**自动生成一个最小 tweak 工程并完整编译一遍**，
//  每一步都记录结果，最后给出「第几步失败、为什么」。
//  这比让用户自己建工程试要快得多，也不会污染他的项目目录。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPSelfTestStage) {
    SPSelfTestStagePending = 0,
    SPSelfTestStageEnv,        // 环境：身份、PATH、目录可写
    SPSelfTestStageToolchain,  // 工具链：clang-16 / ld64 / ldid / make / perl
    SPSelfTestStageTheos,      // Theos：makefiles / logos.pl
    SPSelfTestStageSDK,        // SDK：iPhoneOS*.sdk 完整性
    SPSelfTestStageScaffold,   // 生成最小工程
    SPSelfTestStageBuild,      // 实际编译
    SPSelfTestStageArtifact,   // 产物校验
    SPSelfTestStageDone,
};

@interface SPSelfTestStep : NSObject
@property (nonatomic, assign) SPSelfTestStage stage;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL passed;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, copy, nullable) NSString *hint;   // 失败时怎么办
@end

@interface SPSelfTest : NSObject

/// 开始测试构建。steps 在过程中逐步回调（主线程），最后 result 给出总结。
/// @param logHandler 编译日志逐行回调，便于展示
- (void)runWithLog:(nullable void (^)(NSString *line))logHandler
        stepUpdate:(void (^)(SPSelfTestStep *step))stepUpdate
        completion:(void (^)(BOOL ok, NSArray<SPSelfTestStep *> *steps, NSString *summary))completion;

/// 是否正在跑
@property (nonatomic, readonly) BOOL running;

@end

NS_ASSUME_NONNULL_END
