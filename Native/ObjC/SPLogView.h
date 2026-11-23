//
//  SPLogView.h
//  Workbench —— 虚拟化的日志视图：只渲染可见行，几万行日志也不卡。
//

#import <UIKit/UIKit.h>
#import "SPModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPLogView : UIView

/// 追加一行（内部主线程调用）
- (void)appendLine:(NSString *)line level:(SPLogLevel)level;
- (void)appendLines:(NSArray<SPLogLine *> *)lines;
- (void)clear;
- (void)scrollToBottomAnimated:(BOOL)animated;

/// 复制全部内容
- (NSString *)fullText;

/// 顶部/中间的浮层提示，例如「已过滤 12 行」
- (void)showToast:(NSString *)text;

@property (nonatomic, assign) BOOL autoScroll;
@property (nonatomic, copy, nullable) NSString *highlightFilter;   // 简单的高亮关键词
@property (nonatomic, assign) CGFloat fontSize;

/// 内存里最多保留多少行（超出丢最早的）
@property (nonatomic, assign) NSUInteger maxLines;

@end

NS_ASSUME_NONNULL_END
