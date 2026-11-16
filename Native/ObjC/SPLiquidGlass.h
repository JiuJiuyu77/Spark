//
//  SPLiquidGlass.h
//  Spark —— 液态玻璃（照搬 DnV1eX/LiquidGlassKit 的实现思路）
//
//  私有 API 部分完全照搬：
//    · CABackdropLayer —— 抓取图层背后的内容（Apple 自己在 UITabBar 里用）
//      关键设置：
//        layerUsesCoreImageFilters = NO
//        windowServerAware = YES
//        groupName = UUID（让同一组的 backdrop 共享采样）
//    · CAFilter —— 颜色矩阵、模糊，做折射与调色
//    · _UILiquidLensView 的思路 —— 我们自己实现（原生不对外开放）
//
//  液态透镜（LiquidLensView）的两个状态：
//    · 静止：半透明白色胶囊（resting pill）
//    · 抬起：渐变成完整液态玻璃，带折射
//
//  加速度驱动的形变（照搬它的参数）：
//    accelerationWindowDuration = 0.3s   采样窗口
//    accelerationScaleCoefficient = 0.00005
//    maxScaleDeviation = 0.3             最多形变 30%
//    形变不会超过 maxScaleDeviation，避免位移过快时被拉得很难看
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 背景抓取视图：靠私有类 CABackdropLayer 拿到背后内容
@interface SPBackdropView : UIView
/// 同组 backdrop 共享采样（照搬 LiquidGlassKit 的 groupName）
@property (nonatomic, copy) NSString *backdropGroup;
@end

/// 液态玻璃视图
@interface SPLiquidGlassView : UIView

@property (nonatomic, assign) CGFloat cornerRadius;
/// 玻璃色（浅色下接近白偏蓝，暗色下深蓝，取自 LiquidGlassKit 默认值）
@property (nonatomic, copy, nullable) UIColor *tintColor;
/// 折射强度 0..1（越大边缘弯曲越明显）
@property (nonatomic, assign) CGFloat refraction;
/// 是否有边缘高光
@property (nonatomic, assign) BOOL showsGlare;
/// 是否为「透镜」形态（更小更圆，用于被选中的 tab）
@property (nonatomic, assign) BOOL lensStyle;

- (instancetype)initWithRadius:(CGFloat)radius;

@end

/// 液态选中指示器：在 tab 之间滑动，带加速度形变
@interface SPLiquidLens : UIView

/// 静止态底色（半透明白）
@property (nonatomic, copy, nullable) UIColor *restingColor;
/// 目标位置（tab 的 frame，会在内部收缩 4pt）
@property (nonatomic, assign) CGRect targetFrame;
/// 带弹簧滑动到目标位置，速度影响纵向压扁程度
- (void)moveToTargetAnimated:(BOOL)animated;
/// 按下时抬起（变亮 + 轻微放大）
- (void)setLifted:(BOOL)lifted;

@end

NS_ASSUME_NONNULL_END
