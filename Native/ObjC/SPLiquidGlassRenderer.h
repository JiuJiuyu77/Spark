//
//  SPLiquidGlassRenderer.h
//  Spark —— 液态玻璃渲染器（Metal 实现）
//
//  这份实现按 LiquidGlassKit 的**渲染流程与着色器**移植：
//    · MTKView 子类，用 fullscreenQuad 画一个全屏四边形
//    · 片元着色器 liquidGlassEffect 做 SDF + 折射 + 色散 + 菲涅尔 + 眩光
//    · 背景通过捕获父视图（CABackdropLayer / layer.render）生成纹理
//    · uniforms 用与 ShaderUniforms 一致的内存布局
//
//  与 Swift 版的差异只在语言层：这里全用 ObjC + 结构体直接映射，
//  着色器本身逐字节一致（放在 Native/Shaders/*.metal，由 CI 编成 metallib）。
//

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 与 LiquidGlassKit 的 LiquidGlass.ShaderUniforms 内存布局一致。
/// 用 simd 类型保证对齐与着色器端一致（否则 GPU 读到的会是错位数据）。
typedef struct {
    vector_float2 resolution;
    float contentsScale;
    vector_float2 touchPoint;
    float shapeMergeSmoothness;
    float cornerRadius;
    float cornerRoundnessExponent;
    vector_float4 materialTint;
    float glassThickness;
    float refractiveIndex;
    float dispersionStrength;
    float fresnelDistanceRange;
    float fresnelIntensity;
    float fresnelEdgeSharpness;
    float glareDistanceRange;
    float glareAngleConvergence;
    float glareOppositeSideBias;
    float glareIntensity;
    float glareEdgeSharpness;
    float glareDirectionOffset;
    int32_t rectangleCount;
    vector_float4 rectangles[16];
} SPGlassUniforms;

/// 预设（数值取自 LiquidGlassKit 的 .lens / .thumb）
typedef NS_ENUM(NSInteger, SPGlassPreset) {
    SPGlassPresetLens = 0,   // 选中指示器
    SPGlassPresetThumb,      // 小圆点
};

@interface SPLiquidGlassRenderer : UIView

- (instancetype)initWithPreset:(SPGlassPreset)preset;

@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) SPGlassPreset preset;
/// 玻璃色调（RGBA），为空时用预设值
@property (nonatomic, copy, nullable) UIColor *materialTint;
/// 需要折射的矩形（本视图坐标系，左上原点）
@property (nonatomic, assign) CGRect shapeRect;

/// 父视图变化后调用，重新捕获背景
- (void)refreshBackdrop;

@end

NS_ASSUME_NONNULL_END
