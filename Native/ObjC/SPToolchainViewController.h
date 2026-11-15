//
//  SPToolchainViewController.h
//  Spark —— 工具链页：探测结果、SDK 选择、远程 / CI 配置
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPToolchainViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
