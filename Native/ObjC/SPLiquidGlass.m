//
//  SPLiquidGlass.m
//
//  私有 API 使用说明（照搬 DnV1eX/LiquidGlassKit）：
//    全部通过 NSClassFromString + KVC，不在编译期链接任何私有符号，
//    这样 Apple 改实现时最多是效果退化，不会链接失败。
//

#import "SPLiquidGlass.h"
#import "SPTheme.h"
#import "SPCompat.h"
#import "SPLiquidGlassRenderer.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 私有 API 封装

/// 安全地设置 KVC 属性：类不存在或键不支持时静默跳过
static void SPSetIfPossible(NSObject *obj, NSString *key, id value) {
    if (!obj) return;
    @try {
        [obj setValue:value forKey:key];
    } @catch (NSException *e) {
        // 私有键在各系统版本上不保证存在，忽略即可
    }
}

static Class SPBackdropLayerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cls = NSClassFromString(@"CABackdropLayer");
    });
    return cls;
}

/// CAFilter：Apple 私有滤镜，能直接做颜色矩阵（iOS 13+ 一直在）
static id SPCAFilter(NSString *name) {
    Class filterClass = NSClassFromString(@"CAFilter");
    if (!filterClass) return nil;
    @try {
        SEL sel = @selector(filterWithName:);
        if (![filterClass respondsToSelector:sel]) return nil;
        id (*fn)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
        return fn(filterClass, sel, name);
    } @catch (NSException *e) {
        return nil;
    }
}

/// 给 layer 加一个颜色矩阵滤镜（用于调色与折射的近似）
static void SPApplyColorMatrix(CALayer *layer, const CGFloat m[20]) {
    id filter = SPCAFilter(@"colorMatrix");
    if (!filter) return;
    CGFloat values[20];
    memcpy(values, m, sizeof(values));
    NSValue *boxed = [NSValue valueWithBytes:values objCType:"[20f]"];
    SPSetIfPossible(filter, @"inputColorMatrix", boxed);

    NSMutableArray *filters = [NSMutableArray array];
    if ([layer valueForKey:@"filters"]) {
        id existing = [layer valueForKey:@"filters"];
        if ([existing isKindOfClass:[NSArray class]]) [filters addObjectsFromArray:existing];
    }
    [filters addObject:filter];
    SPSetIfPossible(layer, @"filters", filters);
}

#pragma mark - SPBackdropView

@interface SPBackdropView ()
@property (nonatomic, copy) NSString *groupId;
@end

@implementation SPBackdropView

// 照搬：用私有 CABackdropLayer 抓取背后内容
+ (Class)layerClass {
    Class cls = SPBackdropLayerClass();
    return cls ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.groupId = NSUUID.UUID.UUIDString;

        // 照搬 LiquidGlassKit 的设置
        SPSetIfPossible(self.layer, @"layerUsesCoreImageFilters", @NO);
        SPSetIfPossible(self.layer, @"windowServerAware", @YES);
        SPSetIfPossible(self.layer, @"groupName", self.groupId);
        SPSetIfPossible(self.layer, @"allowsHitTesting", @NO);
    }
    return self;
}

- (void)setBackdropGroup:(NSString *)backdropGroup {
    _backdropGroup = [backdropGroup copy];
    SPSetIfPossible(self.layer, @"groupName", backdropGroup);
}

/// 私有层是否真的可用（有些系统版本上 NSClassFromString 能拿到类，
/// 但用起来没效果）
- (BOOL)isUsable {
    return SPBackdropLayerClass() != nil
        && [self.layer isKindOfClass:SPBackdropLayerClass()];
}

@end

#pragma mark - SPLiquidGlassView

@interface SPLiquidGlassView ()
@property (nonatomic, strong) SPLiquidGlassRenderer *metal;
@end

@implementation SPLiquidGlassView

- (instancetype)initWithRadius:(CGFloat)radius {
    if ((self = [super initWithFrame:CGRectZero])) {
        _cornerRadius = radius;
        _refraction = 0.5;
        _showsGlare = YES;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _cornerRadius = SPRadiusL;
        _refraction = 0.5;
        _showsGlare = YES;
        [self commonInit];
    }
    return self;
}

/// 真正干活的是 Metal 渲染器（SPLiquidGlassRenderer）。
/// 之前这里是我自己拼的「模糊 + 描边 + 渐变」近似实现，
/// 与 LiquidGlassKit 的 SDF + 折射着色器完全是两回事 —— 已整体替换。
- (void)commonInit {
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;

    _metal = [[SPLiquidGlassRenderer alloc] initWithPreset:
              (self.lensStyle ? SPGlassPresetThumb : SPGlassPresetLens)];
    _metal.translatesAutoresizingMaskIntoConstraints = NO;
    _metal.cornerRadius = _cornerRadius;
    [self addSubview:_metal];
    [NSLayoutConstraint activateConstraints:@[
        [_metal.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_metal.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_metal.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_metal.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _metal.cornerRadius = _cornerRadius;
    _metal.shapeRect = self.bounds;
    _metal.materialTint = self.tintColor;
    [_metal refreshBackdrop];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    _metal.cornerRadius = cornerRadius;
    [self setNeedsLayout];
}

- (void)setTintColor:(UIColor *)tintColor {
    _tintColor = tintColor;
    _metal.materialTint = tintColor;
    [_metal setNeedsDisplay];
}

- (void)setShowsGlare:(BOOL)showsGlare {
    _showsGlare = showsGlare;
    [_metal setNeedsDisplay];
}

- (void)refreshColors {
    // 颜色全部交给 Metal 端（materialTint + fresnel / glare 参数）
    [_metal setNeedsDisplay];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self refreshColors];
}

@end

#pragma mark - SPLiquidLens

@interface SPLiquidLens ()
@property (nonatomic, strong) UIView *pill;          // 静止态胶囊
@property (nonatomic, strong) SPLiquidGlassView *glass; // 抬起态
@property (nonatomic, strong) NSMutableArray *history;  // (position, time)
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) BOOL lifted;
@end

@implementation SPLiquidLens

// 照搬 LiquidGlassKit 的形变参数
static const CFTimeInterval kAccelWindow = 0.3;
static const CGFloat kAccelScaleCoeff = 0.00005;
static const CGFloat kMaxScaleDeviation = 0.3;

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _history = [NSMutableArray array];
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;

        // 静止态：半透明白胶囊
        _pill = [[UIView alloc] initWithFrame:self.bounds];
        _pill.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
        _pill.layer.cornerRadius = SPRadiusL;
        if (@available(iOS 13.0, *)) _pill.layer.cornerCurve = kCACornerCurveContinuous;
        _pill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_pill];

        // 抬起态：液态玻璃（默认隐藏）
        _glass = [[SPLiquidGlassView alloc] initWithRadius:SPRadiusL];
        _glass.frame = self.bounds;
        _glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _glass.alpha = 0;
        [self addSubview:_glass];
    }
    return self;
}

- (void)setRestingColor:(UIColor *)restingColor {
    _restingColor = restingColor;
    _pill.backgroundColor = restingColor;
}

- (void)setTargetFrame:(CGRect)targetFrame {
    // 透镜比 tab 略小（照搬：四周留 4pt）
    _targetFrame = CGRectInset(targetFrame, 4, 4);
    if (CGRectIsEmpty(self.frame)) {
        self.frame = _targetFrame;
    } else if (CGRectIsEmpty(_targetFrame)) {
        return;
    }
}

- (void)moveToTargetAnimated:(BOOL)animated {
    if (CGRectIsEmpty(_targetFrame)) return;

    CGRect from = self.frame;
    if (!animated || CGRectIsEmpty(from)) {
        self.frame = _targetFrame;
        return;
    }

    // 记录历史位置，用于算加速度
    CFTimeInterval now = CACurrentMediaTime();
    CGPoint targetCenter = CGPointMake(CGRectGetMidX(_targetFrame), CGRectGetMidY(_targetFrame));
    [_history addObject:@{@"p": [NSValue valueWithCGPoint:targetCenter],
                          @"t": @(now)}];
    if (_history.count > 24) [_history removeObjectAtIndex:0];

    // 形变量由加速度决定（照搬公式）
    CGFloat accel = [self averageAcceleration];
    CGFloat deviation = MIN(kMaxScaleDeviation, accel * kAccelScaleCoeff);
    CGFloat squash = 1.0 - deviation;
    CGFloat stretch = 1.0 + deviation * 0.6;

    self.frame = _targetFrame;

    [UIView animateWithDuration:0.34
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = CGAffineTransformMakeScale(stretch, squash);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.16 delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

/// 照搬：0.3s 窗口内的平均加速度
- (CGFloat)averageAcceleration {
    if (_history.count < 3) return 0;
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray *recent = [NSMutableArray array];
    for (NSDictionary *item in _history) {
        CFTimeInterval t = [item[@"t"] doubleValue];
        if (now - t <= kAccelWindow) [recent addObject:item];
    }
    if (recent.count < 3) return 0;

    CGFloat total = 0;
    NSUInteger n = 0;
    for (NSUInteger i = 2; i < recent.count; i++) {
        CGPoint p0 = [recent[i-2][@"p"] CGPointValue];
        CGPoint p1 = [recent[i-1][@"p"] CGPointValue];
        CGPoint p2 = [recent[i][@"p"] CGPointValue];
        CGFloat dt1 = [recent[i-1][@"t"] doubleValue] - [recent[i-2][@"t"] doubleValue];
        CGFloat dt2 = [recent[i][@"t"] doubleValue] - [recent[i-1][@"t"] doubleValue];
        if (dt1 <= 0 || dt2 <= 0) continue;
        CGFloat v1 = hypot(p1.x - p0.x, p1.y - p0.y) / dt1;
        CGFloat v2 = hypot(p2.x - p1.x, p2.y - p1.y) / dt2;
        total += fabs(v2 - v1) / dt2;
        n++;
    }
    return n ? total / n : 0;
}

- (void)setLifted:(BOOL)lifted {
    if (_lifted == lifted) return;
    _lifted = lifted;

    [UIView animateWithDuration:0.26 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self->_glass.alpha = lifted ? 1.0 : 0.0;
        self->_pill.alpha = lifted ? 0.0 : 1.0;
        self.transform = lifted ? CGAffineTransformMakeScale(1.06, 1.06)
                                : CGAffineTransformIdentity;
    } completion:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _pill.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
    _glass.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
    _glass.lensStyle = YES;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [_glass refreshColors];
}

@end
