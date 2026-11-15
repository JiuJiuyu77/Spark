//
//  SPTheme.h
//  Spark —— 统一的视觉语言（深色、等宽、强调色为 Rein 的薄荷绿）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPTheme : NSObject

// 颜色
@property (class, nonatomic, readonly) UIColor *background;      // #0E1116
@property (class, nonatomic, readonly) UIColor *surface;         // #151A21
@property (class, nonatomic, readonly) UIColor *surfaceHigh;     // #1D242E
@property (class, nonatomic, readonly) UIColor *separator;       // #262E3A
@property (class, nonatomic, readonly) UIColor *text;            // #E6EDF3
@property (class, nonatomic, readonly) UIColor *textDim;         // #8B98A9
@property (class, nonatomic, readonly) UIColor *accent;          // #35D6A4
@property (class, nonatomic, readonly) UIColor *accentDim;       // #1F8F6E
@property (class, nonatomic, readonly) UIColor *warn;            // #F2B73D
@property (class, nonatomic, readonly) UIColor *danger;          // #FF5C68
@property (class, nonatomic, readonly) UIColor *info;            // #58A6FF
@property (class, nonatomic, readonly) UIColor *codeBackground;  // #0B0E12

// 字体
+ (UIFont *)monoFont:(CGFloat)size;
+ (UIFont *)monoFont:(CGFloat)size bold:(BOOL)bold;
+ (UIFont *)uiFont:(CGFloat)size weight:(UIFontWeight)weight;

// 组件
+ (void)styleCard:(UIView *)view;
+ (void)stylePrimaryButton:(UIButton *)button;
+ (void)styleSecondaryButton:(UIButton *)button;
+ (void)styleDangerButton:(UIButton *)button;
+ (CAGradientLayer *)accentGradientForBounds:(CGRect)bounds;

// 日志颜色
+ (UIColor *)colorForLogLevel:(NSInteger)level;

@end

/// 一个带内边距的卡片容器
@interface SPCardView : UIView
@property (nonatomic, strong, readonly) UIView *contentView;
@end

/// 状态小标签
@interface SPBadgeLabel : UILabel
- (void)setText:(NSString *)text color:(UIColor *)color;
@end

NS_ASSUME_NONNULL_END
