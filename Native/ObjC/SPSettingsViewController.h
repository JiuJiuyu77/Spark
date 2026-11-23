//
//  SPSettingsViewController.h
//  Workbench —— 设置页（HIG：分组列表 + 二级页面）
//
//  分组：
//   1. 编译默认值（架构 / 包格式 / Debug / 并行 / 清理 / 补签 / strip）
//   2. 混淆（OLLVM 强度、pass 多选、说明）
//   3. 工具链（内置工具链状态、展开/重装、SDK 导入、路径说明）
//   4. 文件接收（导入 .dyld/.deb/.zip、产物导出位置、清除缓存）
//   5. 构建目标（本机 / 远程 SSH / CI）
//   6. 显示与反馈（触感、屏幕常亮、日志行数、字号）
//   7. 关于
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate,
                                                       UIDocumentPickerDelegate>
@end

NS_ASSUME_NONNULL_END
