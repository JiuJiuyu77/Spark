//
//  SPTheme.h
//  Spark —— 视觉层：样式遵循 Apple HIG，动画统一走 Gasp 缓动。
//
//  设计原则（Apple HIG）：
//   · 用系统语义色（labelColor / systemBackground / separatorColor），自动适配深浅色
//   · 用系统字体 + Dynamic Type（UIFontTextStyle*），尊重用户的字号设置
//   · 圆角/间距贴近系统控件（列表分组卡片 10pt、按钮 12pt）
//   · 图标一律用 SF Symbols，不用自绘符号
//   · 触摸目标不小于 44pt
//
//  动画原则（Gasp）：
//   · 所有动画都从 SPMotion 拿曲线，禁止散落的 magic number
//   · 强调「起手快、收尾软」：入场 easeOut，退场 easeIn，状态切换用弹簧
//   · 尊重「减弱动态效果」辅助功能开关
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Gasp 动画曲线

/// Gasp 动画工具箱：所有动效都从这里取参数，保证全 App 手感一致。
@interface SPMotion : NSObject

/// 极其克制的出现/消失（0.22s easeOut）—— 列表插入、提示条
+ (void)appear:(void (^)(void))animations;
/// 退场（0.16s easeIn）
+ (void)disappear:(void (^)(void))animations completion:(nullable void (^)(void))completion;
/// 状态切换（弹簧，适合选中/高亮/进度跳变）
+ (void)spring:(void (^)(void))animations;
/// 弹性更强的一次「弹一下」（成功提示、注入完成）
+ (void)pop:(UIView *)view;
/// 轻微按压反馈（0.97 → 1.0）
+ (void)pressDown:(UIView *)view;
+ (void)pressUp:(UIView *)view;
/// 数字/进度平滑过渡
+ (void)animate:(void (^)(void))animations duration:(NSTimeInterval)duration;

/// 是否允许动画（跟随「减弱动态效果」）
+ (BOOL)motionAllowed;

/// 触感反馈（跟随设置开关）
+ (void)hapticLight;
+ (void)hapticSuccess;
+ (void)hapticError;

@end

#pragma mark - 颜色与字体

@interface SPTheme : NSObject

// 全部使用系统语义色，深浅色自动切换
+ (UIColor *)background;      // systemGroupedBackground
+ (UIColor *)surface;         // secondarySystemGroupedBackground（分组卡）
+ (UIColor *)surfaceHigh;     // tertiarySystemGroupedBackground
+ (UIColor *)separator;       // separatorColor
+ (UIColor *)text;            // labelColor
+ (UIColor *)textDim;         // secondaryLabelColor
+ (UIColor *)accent;          // systemBlue
+ (UIColor *)success;         // systemGreen
+ (UIColor *)warn;            // systemOrange
+ (UIColor *)danger;          // systemRed
+ (UIColor *)info;            // systemTeal
+ (UIColor *)codeBackground;  // 代码块：浅色下用 secondarySystemBackground，深色下更黑
+ (UIColor *)codeText;

/// 日志配色
+ (UIColor *)colorForLogLevel:(NSInteger)level;

/// 字体：全部基于 UIFontTextStyle，支持 Dynamic Type
+ (UIFont *)title;            // headline
+ (UIFont *)body;             // body
+ (UIFont *)caption;          // caption1
+ (UIFont *)mono:(CGFloat)size;               // 代码：等宽
+ (UIFont *)mono:(CGFloat)size weight:(UIFontWeight)weight;
+ (UIFont *)scaled:(UIFontTextStyle)style weight:(UIFontWeight)weight;

/// 组件样式
+ (void)styleCell:(UITableViewCell *)cell;
+ (void)stylePrimaryButton:(UIButton *)button;
+ (void)styleSecondaryButton:(UIButton *)button;
+ (void)styleDestructiveButton:(UIButton *)button;

/// 统一圆角（HIG：连续曲率）
+ (void)round:(UIView *)view radius:(CGFloat)radius;

@end

#pragma mark - 组件

/// 分组卡片容器：自带 inset padding，配合 UITableViewStyleInsetGrouped 使用
@interface SPCardView : UIView
@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, assign) CGFloat padding;
@end

/// 状态胶囊（HIG 里叫 badge）：文字 + 描边，不给整块铺色
@interface SPBadgeLabel : UILabel
- (void)setText:(NSString *)text color:(UIColor *)color;
@end

/// 毛玻璃背景（HIG 常见于工具栏/浮层），iOS 15+ 用 UIVisualEffectView
@interface SPGlassBar : UIVisualEffectView
@end

NS_ASSUME_NONNULL_END
