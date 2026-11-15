//
//  SPGitViewController.h
//  Spark —— Git 面板（状态 / 暂存 / 提交 / 历史 / 推送）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPGitViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithProjectRoot:(NSString *)root;

@end

NS_ASSUME_NONNULL_END
