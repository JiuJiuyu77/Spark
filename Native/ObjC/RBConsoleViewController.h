//
//  RBConsoleViewController.h
//  ReinBuild —— 构建控制台：日志 + 失败诊断 + 产物
//

#import <UIKit/UIKit.h>
#import "RBModels.h"
#import "RBToolchain.h"

NS_ASSUME_NONNULL_BEGIN

@interface RBConsoleViewController : UIViewController

- (instancetype)initWithProject:(RBProject *)project profile:(RBToolchainProfile *)profile;

/// 构建完成回调（用于刷新上级页面）
@property (nonatomic, copy, nullable) void (^onJobFinished)(RBJob *job);

/// 立即开始构建（viewDidAppear 时如果不是 nil 就自动开跑）
@property (nonatomic, assign) BOOL autoStart;

@end

NS_ASSUME_NONNULL_END
