//
//  SPLiquidGlassRenderer.m
//  Spark —— 液态玻璃 Metal 渲染器
//
//  流程完全对照 LiquidGlassKit 的 LiquidGlassView / LiquidGlassRenderer：
//    1. MTKView + fullscreenQuad 顶点着色器 + liquidGlassEffect 片元着色器
//    2. 背景纹理：把父视图渲染进 CVPixelBuffer（IOSurface，零拷贝）→ MTLTexture
//    3. uniforms 每帧上传，含 rectangles 数组（SDF 并集用）
//    4. 可选模糊（backgroundTextureBlurRadius）用 MPSImageGaussianBlur
//
//  这里没有用 CABackdropLayer 那条路（它在 iOS 26.2+ 失效），
//  直接走 layer.render 到 IOSurface —— 与它的 iOS 26.2 分支等价。
//

#import "SPLiquidGlassRenderer.h"
#import "SPCompat.h"
#import <QuartzCore/QuartzCore.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <CoreVideo/CoreVideo.h>
#import <simd/simd.h>
#include <stddef.h>

// ─────────────────────────────────────────────────────────────
// 预设参数（数值取自 LiquidGlassKit 的 .lens / .thumb）
// ─────────────────────────────────────────────────────────────
typedef struct {
    SPGlassUniforms uniforms;
    double sizeCoefficient;
    double scaleCoefficient;
    double blurRadius;
} SPGlassParams;

static SPGlassParams SPGlassParamsForPreset(SPGlassPreset preset) {
    SPGlassParams p = {0};

    switch (preset) {
        case SPGlassPresetLens: {
            p.uniforms.materialTint = (vector_float4){0, 0, 0, 0};
            p.uniforms.glassThickness = 6;
            p.uniforms.refractiveIndex = 1.1f;
            p.uniforms.dispersionStrength = 15;
            p.uniforms.fresnelDistanceRange = 70;
            p.uniforms.fresnelIntensity = 0;
            p.uniforms.fresnelEdgeSharpness = 0;
            p.uniforms.glareDistanceRange = 30;
            p.uniforms.glareAngleConvergence = 0.1f;
            p.uniforms.glareOppositeSideBias = 1;
            p.uniforms.glareIntensity = 0.1f;
            p.uniforms.glareEdgeSharpness = -0.1f;
            p.uniforms.glareDirectionOffset = -(float)M_PI / 4.0f;
            p.sizeCoefficient = 1.1;
            p.scaleCoefficient = 0.8;
            p.blurRadius = 0;
            break;
        }
        case SPGlassPresetThumb: {
            p.uniforms.materialTint = (vector_float4){0.9f, 0.95f, 1.0f, 0.15f};
            p.uniforms.glassThickness = 10;
            p.uniforms.refractiveIndex = 1.11f;
            p.uniforms.dispersionStrength = 5;
            p.uniforms.fresnelDistanceRange = 70;
            p.uniforms.fresnelIntensity = 0;
            p.uniforms.fresnelEdgeSharpness = 0;
            p.uniforms.glareDistanceRange = 30;
            p.uniforms.glareAngleConvergence = 0;
            p.uniforms.glareOppositeSideBias = 0;
            p.uniforms.glareIntensity = 0.01f;
            p.uniforms.glareEdgeSharpness = -0.2f;
            p.uniforms.glareDirectionOffset = (float)M_PI * 0.9f;
            p.sizeCoefficient = 1.0;
            p.scaleCoefficient = 1.0;
            p.blurRadius = 0;
            break;
        }
    }
    p.uniforms.cornerRoundnessExponent = 2;  // 1=菱形 2=圆 4=方圆形
    return p;
}

#pragma mark - 渲染器

@interface SPLiquidGlassRenderer ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property (nonatomic, strong) id<MTLBuffer> uniformsBuffer;
@property (nonatomic, strong, nullable) id<MTLTexture> backgroundTexture;
@property (nonatomic, strong, nullable) CIContext *ciContext;
@property (nonatomic, assign) CGSize lastDrawableSize;
@property (nonatomic, strong, nullable) id<MTLTexture> renderTarget;
@end

// 布局断言：Metal 端 ShaderUniforms 的字段顺序与对齐必须和这里一致。
// 算错任何一个字段偏移，GPU 读到的就是错位数据 —— 表现为「画面一片花」，
// 而且不会有任何报错，极难排查。
//
// Metal 端 struct 的规则：float2 对齐 8，float4 对齐 16，整体对齐 16。
// 按这个规则算出来是 384 字节（rectangles 在偏移 128）。
_Static_assert(sizeof(SPGlassUniforms) == 384, "SPGlassUniforms 大小必须与 Metal 端一致（384）");
_Static_assert(offsetof(SPGlassUniforms, materialTint) == 48, "materialTint 偏移应为 48");
_Static_assert(offsetof(SPGlassUniforms, rectangleCount) == 112, "rectangleCount 偏移应为 112");
_Static_assert(offsetof(SPGlassUniforms, rectangles) == 128, "rectangles 偏移应为 128");

@implementation SPLiquidGlassRenderer

- (instancetype)initWithPreset:(SPGlassPreset)preset {
    // 直接用 MTKView 作自身（与 LiquidGlassView 一致）
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _preset = preset;
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) { SPLog(@"[!] Metal 不可用"); return self; }

        _queue = [_device newCommandQueue];
        _uniformsBuffer = [_device newBufferWithLength:sizeof(SPGlassUniforms)
                                              options:MTLResourceStorageModeShared];

        [self buildPipeline];

        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.clipsToBounds = NO;
    }
    return self;
}

/// 编译渲染管线：着色器在 default.metallib 里（CI 用 xcrun metal 编译）
- (void)buildPipeline {
    NSError *err = nil;
    id<MTLLibrary> lib = [self.device newDefaultLibrary];
    if (!lib) {
        // 退路：从 main bundle 的液态玻璃资源里找
        NSURL *url = [NSBundle.mainBundle URLForResource:@"LiquidGlassKitShaderResources"
                                           withExtension:@"bundle"];
        if (url) {
            id<MTLLibrary> l2 = [self.device newLibraryWithURL:url error:&err];
            if (l2) lib = l2;
        }
    }
    if (!lib) {
        SPLog(@"[!] 找不到 Metal 库（default.metallib），液态玻璃不可用：%@",
              err.localizedDescription);
        return;
    }

    id<MTLFunction> vf = [lib newFunctionWithName:@"fullscreenQuad"];
    id<MTLFunction> ff = [lib newFunctionWithName:@"liquidGlassEffect"];
    if (!vf || !ff) {
        SPLog(@"[!] 着色器函数缺失：vertex=%@ fragment=%@", vf, ff);
        return;
    }

    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = vf;
    d.fragmentFunction = ff;
    d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    self.pipeline = [self.device newRenderPipelineStateWithDescriptor:d error:&err];
    if (err) SPLog(@"[!] 管线创建失败：%@", err.localizedDescription);
}

/// 自身透明：液态玻璃靠背景纹理 + 着色器输出，不需要不透明层
- (BOOL)isOpaque { return NO; }

- (void)setPreset:(SPGlassPreset)preset {
    _preset = preset;
    [self setNeedsDisplay];
}

- (void)setShapeRect:(CGRect)shapeRect {
    _shapeRect = shapeRect;
    [self setNeedsDisplay];
}

- (void)setCornerRadius:(CGFloat)r {
    _cornerRadius = r;
    [self setNeedsDisplay];
}

#pragma mark - 背景捕获

- (void)refreshBackdrop {
    [self captureBackground];
}

/// 把父视图（去掉自己）渲染到 IOSurface，再包成 MTLTexture
- (void)captureBackground {
    UIView *host = self.superview;
    if (!host || self.bounds.size.width < 1 || self.bounds.size.height < 1) return;

    SPGlassParams params = SPGlassParamsForPreset(self.preset);
    CGFloat scale = self.contentScaleFactor * params.scaleCoefficient;
    CGSize capSize = CGSizeMake(self.bounds.size.width * params.sizeCoefficient,
                                self.bounds.size.height * params.sizeCoefficient);
    if (capSize.width < 1 || capSize.height < 1) return;

    // 本视图在宿主坐标系中的位置（用 presentation layer 以便动画期间跟随）
    CALayer *mine = self.layer.presentationLayer ?: self.layer;
    CGRect frameInHost = [mine convertRect:mine.bounds toLayer:host.layer];
    CGRect capRect = CGRectMake(CGRectGetMidX(frameInHost) - capSize.width / 2,
                                CGRectGetMidY(frameInHost) - capSize.height / 2,
                                capSize.width, capSize.height);

    NSDictionary *attrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    CVPixelBufferRef pb = NULL;
    CVReturn cvr = CVPixelBufferCreate(kCFAllocatorDefault,
                                       (size_t)(capSize.width * scale),
                                       (size_t)(capSize.height * scale),
                                       kCVPixelFormatType_32BGRA,
                                       (__bridge CFDictionaryRef)attrs, &pb);
    if (cvr != kCVReturnSuccess || !pb) return;

    if (!self.ciContext) {
        self.ciContext = [CIContext contextWithMTLDevice:self.device
                                                 options:@{kCIContextWorkingColorSpace: (id)NSNull.null}];
    }

    // 渲染宿主视图到 context（跳过自己）
    BOOL wasHidden = self.hidden;
    self.hidden = YES;
    CGContextRef ctx = NULL;
    CVPixelBufferLockBaseAddress(pb, 0);
    void *base = CVPixelBufferGetBaseAddress(pb);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pb);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    ctx = CGBitmapContextCreate(base,
                                CVPixelBufferGetWidth(pb),
                                CVPixelBufferGetHeight(pb),
                                8, bytesPerRow, cs,
                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (ctx) {
        CGContextScaleCTM(ctx, scale, scale);
        CGContextTranslateCTM(ctx, -capRect.origin.x, -capRect.origin.y);
        CALayer *hostLayer = host.layer.presentationLayer ?: host.layer;
        [hostLayer renderInContext:ctx];
        CGContextRelease(ctx);
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    self.hidden = wasHidden;

    // 包成 Metal 纹理
    CVMetalTextureCacheRef cache = NULL;
    CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, self.device, NULL, &cache);
    if (cache) {
        CVMetalTextureRef texRef = NULL;
        size_t w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb);
        CVReturn r = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache,
                                                              pb, NULL,
                                                              MTLPixelFormatBGRA8Unorm,
                                                              w, h, 0, &texRef);
        if (r == kCVReturnSuccess && texRef) {
            id<MTLTexture> tex = CVMetalTextureGetTexture(texRef);
            // 可选模糊
            if (params.blurRadius > 0 && tex) {
                tex = [self blurred:tex radius:params.blurRadius];
            }
            self.backgroundTexture = tex;
            CFRelease(texRef);
        }
        CVMetalTextureCacheFlush(cache, 0);
        CFRelease(cache);
    }
    CVPixelBufferRelease(pb);

    [self setNeedsDisplay];
}

- (id<MTLTexture>)blurred:(id<MTLTexture>)src radius:(double)radius {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:src.pixelFormat
                                                                                    width:src.width
                                                                                   height:src.height
                                                                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    id<MTLTexture> dst = [self.device newTextureWithDescriptor:desc];
    if (!dst) return src;

    id<MTLCommandBuffer> cb = [self.queue commandBuffer];
    MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc] initWithDevice:self.device
                                                                       sigma:radius * 2.0];
    [blur encodeToCommandBuffer:cb sourceTexture:src destinationTexture:dst];
    [cb commit];
    [cb waitUntilCompleted];
    return dst;
}

#pragma mark - 绘制

- (void)drawRect:(CGRect)rect {
    if (!self.pipeline || !self.queue) return;

    CGSize drawable = self.bounds.size;
    if (drawable.width < 1 || drawable.height < 1) return;
    CGFloat scale = self.contentScaleFactor;
    CGSize px = CGSizeMake(drawable.width * scale, drawable.height * scale);

    // 复用 render target：每次 newTexture 在底栏滑动时会大量重建纹理，
    // 造成明显掉帧。尺寸不变就复用同一张。
    if (!self.renderTarget ||
        self.renderTarget.width != (NSUInteger)px.width ||
        self.renderTarget.height != (NSUInteger)px.height) {
        MTLTextureDescriptor *desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:(NSUInteger)px.width
                                                              height:(NSUInteger)px.height
                                                           mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        self.renderTarget = [self.device newTextureWithDescriptor:desc];
    }
    if (!self.renderTarget) return;

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = self.renderTarget;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);

    SPGlassParams params = SPGlassParamsForPreset(self.preset);
    SPGlassUniforms u = params.uniforms;
    u.resolution = (vector_float2){(float)px.width, (float)px.height};
    u.contentsScale = (float)scale;
    u.cornerRadius = (float)self.cornerRadius;
    if (self.materialTint) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [self.materialTint getRed:&r green:&g blue:&b alpha:&a];
        u.materialTint = (vector_float4){(float)r, (float)g, (float)b, (float)a};
    }
    CGRect r = self.shapeRect.size.width > 0 ? self.shapeRect : self.bounds;
    u.rectangleCount = 1;
    u.rectangles[0] = (vector_float4){(float)CGRectGetMinX(r), (float)CGRectGetMinY(r),
                                      (float)CGRectGetWidth(r), (float)CGRectGetHeight(r)};
    memcpy(self.uniformsBuffer.contents, &u, sizeof(u));

    id<MTLCommandBuffer> cb = [self.queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:self.pipeline];
    // 索引必须是 0：片元着色器声明的是 [[buffer(0)]]
    [enc setVertexBytes:&u length:sizeof(u) atIndex:0];
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:0];
    if (self.backgroundTexture) {
        [enc setFragmentTexture:self.backgroundTexture atIndex:0];
    }
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];

    // 同步等待再转 CGImage 是必要的（CALayer.contents 要 CPU 可见的图），
    // 但只在纹理重建时做一次转换，避免每帧创建 CGImage。
    [cb commit];
    [cb waitUntilCompleted];

    CGImageRef img = [self.ciContext createCGImage:[CIImage imageWithMTLTexture:self.renderTarget options:nil]
                                          fromRect:CGRectMake(0, 0, px.width, px.height)];
    if (img) {
        self.layer.contents = (__bridge_transfer id)img;
        self.layer.contentsScale = scale;
        self.layer.contentsGravity = kCAGravityResize;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize px = CGSizeMake(self.bounds.size.width * self.contentScaleFactor,
                           self.bounds.size.height * self.contentScaleFactor);
    if (!CGSizeEqualToSize(px, self.lastDrawableSize)) {
        self.lastDrawableSize = px;
        self.backgroundTexture = nil;   // 尺寸变了要重抓
        [self captureBackground];
    }
}

@end
