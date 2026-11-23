//
//  SPMountsViewController.h
//  Workbench —— 挂载管理（WebDAV / SMB）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SPMount;

@interface SPMountsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

/// 浏览某个挂载点的远端目录
@interface SPMountBrowser : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithMount:(SPMount *)mount path:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
