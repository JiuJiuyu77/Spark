//
//  SPAnimationKit.h
//  Spark —— 更细腻的动效（在 SPMotion 之上扩展）
//
//  参考点：Swiftgram / iOS 26 的手感
//   · 交错入场（stagger）：列表项依次淡入，而不是整块出现
//   · 高亮涟漪（ripple）：点击行时从触点扩散
//   · 数字滚动（number ticker）：计时器变化不是跳字
//   · 进度环（ring）：安装/下载用环形进度替代细条
//   · 抽屉弹起（sheet spring）：从底部弹起的卡片带轻微过冲
//   · 骨架加载（skeleton）：等待时用呼吸感的占位块
//
//  全部尊重「减弱动态效果」开关；关闭时直接给终态。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPAnimationKit : NSObject

/// 交错入场：给一组视图依次设置初始位移+透明，然后错峰动画到正常状态
+ (void)stagger:(NSArray<UIView *> *)views offset:(CGFloat)offset;

/// 涟漪高亮：在 view 上以 point 为中心扩散一个圆
+ (void)rippleIn:(UIView *)view at:(CGPoint)point color:(nullable UIColor *)color;

/// 呼吸光晕（给「正在构建」等状态用），返回的 layer 需要保留引用
+ (CALayer *)breatheGlowOn:(UIView *)view color:(UIColor *)color;

/// 数字变化动画（例如 00:42 → 00:43 平滑过渡）
+ (void)animateNumberLabel:(UILabel *)label from:(NSInteger)from to:(NSInteger)to format:(nullable NSString *(^)(NSInteger))format;

/// 从底部弹出一个 view（带过冲），完成后回调
+ (void)springInFromBottom:(UIView *)view completion:(nullable void (^)(void))completion;
+ (void)springOutToBottom:(UIView *)view completion:(nullable void (^)(void))completion;

/// 骨架屏：在 view 上铺一层呼吸灰
+ (void)skeletonize:(UIView *)view;
+ (void)deskeletonize:(UIView *)view;

@end

/// 环形进度
@interface SPRingProgressView : UIView
@property (nonatomic, assign) CGFloat progress;          // 0..1
@property (nonatomic, strong) UIColor *progressColor;
@property (nonatomic, assign) CGFloat lineWidth;
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
