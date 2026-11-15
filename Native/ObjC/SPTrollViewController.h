//
//  SPTrollViewController.h
//  Spark —— 巨魔（TrollStore）注入器
//
//  参考 Lessica/TrollFools（MIT）的注入流程，用设备上现成的
//  insert_dylib / install_name_tool / ldid / chown 一步步完成：
//    选 App → 选插件（dylib / framework / bundle / .deb / .zip）→ 预览计划 → 注入
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPTrollViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

/// 工具探测结果摘要（用于顶部状态条）
- (void)refreshTools;

@end

NS_ASSUME_NONNULL_END
