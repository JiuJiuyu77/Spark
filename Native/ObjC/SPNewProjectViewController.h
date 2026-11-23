//
//  SPNewProjectViewController.h
//  Workbench —— 新建工程表单（对齐 dylix 的 StudioCreate）
//
//  与旧版 Alert 输入框的区别：
//  · 独立的表单页，模板分区选择（Objective-C / Logos / 纯动态库）
//  · 五个字段：项目名称、包标识、作者、版本、目标 Bundle ID
//  · 生成 .plist 过滤器 + control + MobileCompiler.json，与 dylix 一致
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SPNewProjectCompletion)(NSString * _Nullable createdPath);

@interface SPNewProjectViewController : UITableViewController

/// createdPath 为 nil 表示取消
@property (nonatomic, copy, nullable) SPNewProjectCompletion onFinish;

@end

NS_ASSUME_NONNULL_END