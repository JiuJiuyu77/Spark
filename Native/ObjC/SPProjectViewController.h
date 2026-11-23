//
//  SPProjectViewController.h
//  Workbench —— 单个项目的构建面板（选项 + 快捷操作）
//

#import <UIKit/UIKit.h>
#import "SPModels.h"
#import "SPToolchain.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPProjectViewController : UIViewController

- (instancetype)initWithProject:(SPProject *)project;

/// 构建成功或选项变化时回调给列表页
@property (nonatomic, copy, nullable) void (^onProjectUpdated)(SPProject *project);

@end

NS_ASSUME_NONNULL_END
