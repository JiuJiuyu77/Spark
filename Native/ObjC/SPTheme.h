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

#pragma mark - 设计令牌（视觉对齐的唯一来源）
//
// 之前各页面各写各的：圆角 8/9/10/12/16/18/20 七种，
// 页边距 8/10/12/16/20/32 六种，看起来就像拼起来的。
// 这里统一成一套 4pt 基准的刻度，所有页面只准用这些常量。

/// 间距刻度（4pt 基准）
typedef NS_ENUM(NSInteger, SPSpace) {
    SPSpaceXXS = 4,
    SPSpaceXS  = 8,
    SPSpaceS   = 12,
    SPSpaceM   = 16,   // 默认页边距
    SPSpaceL   = 20,
    SPSpaceXL  = 24,
    SPSpaceXXL = 32,
    SPSpaceHuge = 28,   // 悬浮栏左右外缩
};

/// 圆角刻度
typedef NS_ENUM(NSInteger, SPRadius) {
    SPRadiusS  = 8,    // 小控件：徽标、输入框
    SPRadiusM  = 12,   // 卡片、按钮（默认）
    SPRadiusL  = 16,   // 大卡片
    SPRadiusXL = 22,   // 悬浮栏、弹层
};

/// 常用尺寸
FOUNDATION_EXPORT const CGFloat SPIconSizeSmall;    // 16
FOUNDATION_EXPORT const CGFloat SPIconSizeMedium;   // 22
FOUNDATION_EXPORT const CGFloat SPIconSizeLarge;    // 28
FOUNDATION_EXPORT const CGFloat SPButtonHeight;     // 48
FOUNDATION_EXPORT const CGFloat SPFloatingBarHeight;// 60
FOUNDATION_EXPORT const CGFloat SPFloatingBarInset; // 74（内容需要留出的底部空间）
FOUNDATION_EXPORT const CGFloat SPFloatingBarSideInset; // 28

@interface SPMetric : NSObject
/// 正文页边距（几乎每页都用）
+ (CGFloat)pageMargin;
/// 分组之间、区块之间的标准间距
+ (CGFloat)sectionGap;
/// 行内元素间距
+ (CGFloat)inlineGap;
@end

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

#pragma mark - 表格统一封装
//
// 之前 23 个页面各写各的：rowHeight 有 62 / 64 / AutomaticDimension 三种，
// separatorColor、背景色、选区样式也各不相同 —— 这是「界面乱」的主要来源之一。
// 统一走这两个工厂方法，改一处全局生效。

/// 标准分组表格（圆角卡片、透明背景、语义色分隔线、自适应行高）
FOUNDATION_EXPORT UITableView *SPMakeInsetTable(id<UITableViewDataSource, UITableViewDelegate> owner);

/// 给表格套上统一样式的玻璃头部（图标 + 标题 + 副标题）
FOUNDATION_EXPORT UIView *SPTableHeader(NSString *symbol,
                                        NSString *title,
                                        NSString *subtitle,
                                        UIColor *tint,
                                        CGFloat width);
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
