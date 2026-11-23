//
//  SPDiffViewController.h
//  Workbench —— 差异查看（参考 Dylix 的 GitDiffView）
//
//  之前在 Git 页点 diff 只是把文本丢进编辑器，看不出改了哪几行。
//  这里做行级着色：新增绿底、删除红底、@@ 头蓝色、上下文灰色。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPDiffViewController : UIViewController

/// @param diffText  `git diff` 的原始输出
/// @param title     标题（一般是文件名）
- (instancetype)initWithDiff:(NSString *)diffText title:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
