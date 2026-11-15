//
//  SPProjectsViewController.h
//  Spark —— 项目列表（最近项目 + 新建 + 扫描）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 当用户想跳到「工具链」标签时发这个通知
extern NSString *const SPOpenToolchainTabNotification;
/// 当新建项目成功时发这个，附带路径
extern NSString *const SPProjectCreatedNotification;

@interface SPProjectsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

- (void)reloadAll;

@end

NS_ASSUME_NONNULL_END
