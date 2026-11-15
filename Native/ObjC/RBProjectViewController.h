//
//  RBProjectViewController.h
//  ReinBuild —— 单个项目的构建面板（选项 + 快捷操作）
//

#import <UIKit/UIKit.h>
#import "RBModels.h"
#import "RBToolchain.h"

NS_ASSUME_NONNULL_BEGIN

@interface RBProjectViewController : UIViewController

- (instancetype)initWithProject:(RBProject *)project;

/// 构建成功或选项变化时回调给列表页
@property (nonatomic, copy, nullable) void (^onProjectUpdated)(RBProject *project);

@end

NS_ASSUME_NONNULL_END
