//
//  SPGlassKit.h
//  Spark —— 模拟液态玻璃 + 悬浮底部栏
//
//  iOS 26 的 Liquid Glass 在低版本没有 API，这里用「模糊 + 高光描边 + 折射渐变
//  + 弹簧浮起」模拟出接近的观感：
//   · SPFloatTabBar  悬浮、圆角、胶囊状，滚动时轻微缩放，选中项有光晕
//   · SPGlassCard    玻璃卡片（替代纯色 SPCardView 的视觉升级）
//   · SPGlassButton  玻璃按钮样式
//

#import <UIKit/UIKit.h>
#import "SPLiquidGlass.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 玻璃材质

@interface SPGlassMaterial : NSObject

/// 给一个视图铺上「液态玻璃」：模糊层 + 高光 + 折射
/// @param tint 可选的色调（nil = 中性玻璃）
+ (void)applyTo:(UIView *)view cornerRadius:(CGFloat)radius tint:(nullable UIColor *)tint;

/// 玻璃描边（1pt，深浅色各一套颜色）
+ (CALayer *)specularBorderForBounds:(CGRect)bounds cornerRadius:(CGFloat)radius;
/// 玻璃内部高光渐变（上亮下暗）
+ (CAGradientLayer *)specularHighlightForBounds:(CGRect)bounds cornerRadius:(CGFloat)radius;

@end

#pragma mark - 玻璃卡片

@interface SPGlassCard : UIView
@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, assign) CGFloat padding;
@property (nonatomic, assign) CGFloat cornerRadius;
/// 轻微按下反馈（列表行常用）
- (void)press;
- (void)releasePressed;
@end

#pragma mark - 悬浮底部栏

@protocol SPFloatTabBarDelegate <NSObject>
- (void)floatTabBar:(id)bar didSelectIndex:(NSInteger)index;
@end

@interface SPFloatTabBar : UIView

@property (nonatomic, weak) id<SPFloatTabBarDelegate> delegate;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray<NSString *> *symbols;
@property (nonatomic, copy) NSArray<NSString *> *selectedSymbols;

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles
                       symbols:(NSArray<NSString *> *)symbols
               selectedSymbols:(NSArray<NSString *> *)selectedSymbols;

/// 滚动方向反馈：向下滚略缩，向上滚复原（模仿系统 tab bar）
- (void)setScrolledDown:(BOOL)scrolledDown;

@end

NS_ASSUME_NONNULL_END
