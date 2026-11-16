//
//  SPLiquidGlass.m
//
//  私有 API 使用说明（照搬 DnV1eX/LiquidGlassKit）：
//    全部通过 NSClassFromString + KVC，不在编译期链接任何私有符号，
//    这样 Apple 改实现时最多是效果退化，不会链接失败。
//

#import "SPLiquidGlass.h"
#import "SPTheme.h"
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

@end

#pragma mark - SPLiquidGlassView

@interface SPLiquidGlassView ()
@property (nonatomic, strong) SPBackdropView *backdrop;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, strong) CAShapeLayer *rimLayer;
@property (nonatomic, strong) CAGradientLayer *glareLayer;
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

- (void)commonInit {
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;

    // 1) 背景抓取（私有 API）
    _backdrop = [[SPBackdropView alloc] initWithFrame:self.bounds];
    _backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    _backdrop.layer.cornerRadius = _cornerRadius;
    _backdrop.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) _backdrop.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_backdrop];
    [NSLayoutConstraint activateConstraints:@[
        [_backdrop.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_backdrop.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_backdrop.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_backdrop.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    // 2) 色调层（LiquidGlassKit 的默认 tint）
    _tintView = [[UIView alloc] initWithFrame:self.bounds];
    _tintView.translatesAutoresizingMaskIntoConstraints = NO;
    _tintView.userInteractionEnabled = NO;
    _tintView.layer.cornerRadius = _cornerRadius;
    if (@available(iOS 13.0, *)) _tintView.layer.cornerCurve = kCACornerCurveContinuous;
    _tintView.clipsToBounds = YES;
    [self addSubview:_tintView];
    [NSLayoutConstraint activateConstraints:@[
        [_tintView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_tintView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_tintView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_tintView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    // 3) 边缘高光（Fresnel）
    _rimLayer = [CAShapeLayer layer];
    _rimLayer.fillColor = UIColor.clearColor.CGColor;
    _rimLayer.lineWidth = 1;
    [self.layer addSublayer:_rimLayer];

    // 4) 斜向高光条纹（Glare，照搬 glareAngleConvergence = -π/4）
    _glareLayer = [CAGradientLayer layer];
    _glareLayer.startPoint = CGPointMake(0.0, 0.0);
    _glareLayer.endPoint = CGPointMake(1.0, 1.0);
    _glareLayer.cornerRadius = _cornerRadius;
    _glareLayer.opacity = 0.5f;
    [self.layer addSublayer:_glareLayer];

    [self refreshColors];
    [self installRefractionFilter];
}

/// 用 CAFilter 做「折射」近似：
/// 真正的折射需要在 Metal 里重采样背景，这里用轻微的模糊 + 色散模拟
/// （LiquidGlassKit 在低端设备上也是这么降级的）
- (void)installRefractionFilter {
    if (self.refraction <= 0) return;

    id blur = SPCAFilter(@"gaussianBlur");
    if (blur) {
        SPSetIfPossible(blur, @"inputRadius", @(1.0 + self.refraction * 1.5));
        SPSetIfPossible(_backdrop.layer, @"filters", @[blur]);
    }
}

- (void)refreshColors {
    BOOL dark = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);

    // 照搬 LiquidGlassKit 的默认 tint：
    // 深色 rgba(0, 0.05, 0.10, 0.80) / 浅色 rgba(0.90, 0.95, 1, 0.80)
    UIColor *tint = self.tintColor;
    if (!tint) {
        tint = dark ? [UIColor colorWithRed:0.0 green:0.05 blue:0.10 alpha:0.80]
                    : [UIColor colorWithRed:0.90 green:0.95 blue:1.0 alpha:0.80];
    }
    _tintView.backgroundColor = tint;

    _rimLayer.strokeColor = dark
        ? [UIColor colorWithWhite:1.0 alpha:0.28].CGColor
        : [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;

    _glareLayer.colors = dark
        ? @[(id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
            (id)[UIColor clearColor].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor]
        : @[(id)[UIColor colorWithWhite:1.0 alpha:0.55].CGColor,
            (id)[UIColor clearColor].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor];
    _glareLayer.hidden = !self.showsGlare;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    _backdrop.layer.cornerRadius = cornerRadius;
    _tintView.layer.cornerRadius = cornerRadius;
    _glareLayer.cornerRadius = cornerRadius;
    [self setNeedsLayout];
}

- (void)setTintColor:(UIColor *)tintColor {
    _tintColor = tintColor;
    [self refreshColors];
}

- (void)setShowsGlare:(BOOL)showsGlare {
    _showsGlare = showsGlare;
    _glareLayer.hidden = !showsGlare;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _rimLayer.frame = b;
    _rimLayer.path = [UIBezierPath bezierPathWithRoundedRect:b
                                               cornerRadius:_cornerRadius].CGPath;
    _glareLayer.frame = b;
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
