//
//  SPTrollViewController.h
//  Spark —— 巨魔（TrollStore）注入器
//  交互照搬 TrollFools：App 列表 → 注入面板
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SPTrollApp;
@class SPTrollInjectPanel;

/// 首页：已安装 App 列表（搜索 + 点击进入注入面板）
@interface SPTrollViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (void)reloadApps;
@end

/// 注入面板：插件列表 + 选项 + 执行
@interface SPTrollInjectPanel : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithApp:(SPTrollApp *)app;

/// 注入结束（无论成败）回调
@property (nonatomic, copy, nullable) void (^onFinished)(void);

@end

NS_ASSUME_NONNULL_END
