//
//  SPGlassKit.m
//
//  液态玻璃视觉参考 sunimp/TabBar（MIT）的设计思路：
//    · 胶囊容器：内容高 56，内边距 4，总高 64，圆角 = 高度/2
//    · 选中指示：一个「液态透镜」—— 比容器略小的圆角矩形，
//      用弹簧从旧位置滑到新位置，同时纵向轻微压缩再回弹（水感）
//    · 背景：UIVisualEffectView 模糊 + 极轻的色调叠层
//    · 细描边：上亮下暗模拟玻璃边缘折射
//
//  没有照搬它的 CAFilter 私有 API 与 Lottie 依赖 —— 只借视觉参数，
//  实现全部用公开 API，保证 TrollStore 环境稳定运行。
//

#import "SPGlassKit.h"
#import "SPTheme.h"

#pragma mark - 玻璃材质

@implementation SPGlassMaterial

+ (void)applyTo:(UIView *)view cornerRadius:(CGFloat)radius tint:(UIColor *)tint {
    if (!view) return;

    // 1) 模糊
    UIVisualEffectView *blur = nil;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) { blur = (UIVisualEffectView *)sub; break; }
    }
    if (!blur) {
        blur = [[UIVisualEffectView alloc] initWithEffect:
                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        blur.translatesAutoresizingMaskIntoConstraints = NO;
        blur.userInteractionEnabled = NO;
        [view insertSubview:blur atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [blur.topAnchor constraintEqualToAnchor:view.topAnchor],
            [blur.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [blur.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [blur.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        ]];
    }

    // 2) 色调叠层（很轻，只负责偏色，不抢背景）
    if (tint) {
        UIView *tintView = nil;
        for (UIView *sub in view.subviews) {
            if ([sub.restorationIdentifier isEqualToString:@"sp.glass.tint"]) { tintView = sub; break; }
        }
        if (!tintView) {
            tintView = [[UIView alloc] init];
            tintView.restorationIdentifier = @"sp.glass.tint";
            tintView.userInteractionEnabled = NO;
            tintView.translatesAutoresizingMaskIntoConstraints = NO;
            [view insertSubview:tintView aboveSubview:blur];
            [NSLayoutConstraint activateConstraints:@[
                [tintView.topAnchor constraintEqualToAnchor:view.topAnchor],
                [tintView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
                [tintView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
                [tintView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
            ]];
        }
        tintView.backgroundColor = [tint colorWithAlphaComponent:0.10];
        tintView.layer.cornerRadius = radius;
        if (@available(iOS 13.0, *)) tintView.layer.cornerCurve = kCACornerCurveContinuous;
        tintView.clipsToBounds = YES;
    }

    // 3) 描边（上亮下暗）
    CALayer *border = [self specularBorderForBounds:CGRectZero cornerRadius:radius];
    border.name = @"sp.glass.border";
    for (CALayer *l in view.layer.sublayers) {
        if ([l.name isEqualToString:@"sp.glass.border"]) [l removeFromSuperlayer];
    }
    [view.layer addSublayer:border];
    border.frame = view.bounds;

    view.clipsToBounds = NO;
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;

    // 4) 外投影
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.18;
    view.layer.shadowRadius = 18;
    view.layer.shadowOffset = CGSizeMake(0, 8);
    view.layer.masksToBounds = NO;
}

+ (CALayer *)specularBorderForBounds:(CGRect)bounds cornerRadius:(CGFloat)radius {
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.frame = bounds;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius].CGPath;
    shape.fillColor = UIColor.clearColor.CGColor;
    shape.lineWidth = 1.0;
    BOOL dark = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    shape.strokeColor = dark
        ? [UIColor colorWithWhite:1.0 alpha:0.30].CGColor
        : [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
    return shape;
}

@end

#pragma mark - 玻璃卡片

@interface SPGlassCard ()
@property (nonatomic, strong) UIView *container;
@end

@implementation SPGlassCard

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _padding = SPSpaceM;
        _cornerRadius = SPRadiusL;

        _container = [[UIView alloc] init];
        _container.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_container];
        [NSLayoutConstraint activateConstraints:@[
            [_container.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_container.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_container.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_container.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        _contentView = _container;

        [SPGlassMaterial applyTo:_container cornerRadius:_cornerRadius tint:nil];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (CALayer *l in _container.layer.sublayers) {
        if ([l.name isEqualToString:@"sp.glass.border"]) l.frame = _container.bounds;
    }
}

- (void)press {
    [SPMotion pressDown:_container];
}

- (void)releasePressed {
    [SPMotion pressUp:_container];
}

@end

#pragma mark - 悬浮底部栏

@interface SPFloatTabBar ()
@property (nonatomic, strong) UIView *capsule;          // 胶囊容器
@property (nonatomic, strong) SPLiquidLens *lens;        // 液态选中指示
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, assign) NSInteger lensIndex;
@property (nonatomic, assign) BOOL didSetup;
@end

@implementation SPFloatTabBar

static CGFloat const kItemHeight = 56;   // 参考 TabBar 的 itemHeight
static CGFloat const kInnerInset = 4;    // 参考 TabBar 的 innerInset

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles
                       symbols:(NSArray<NSString *> *)symbols
               selectedSymbols:(NSArray<NSString *> *)selectedSymbols {
    if ((self = [super initWithFrame:CGRectZero])) {
        _titles = [titles copy];
        _symbols = [symbols copy];
        _selectedSymbols = [selectedSymbols copy];
        _buttons = [NSMutableArray array];
        _lensIndex = 0;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _buttons = [NSMutableArray array];
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = UIColor.clearColor;

    // 胶囊容器
    _capsule = [[UIView alloc] init];
    _capsule.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_capsule];
    [NSLayoutConstraint activateConstraints:@[
        [_capsule.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_capsule.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_capsule.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_capsule.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_capsule.heightAnchor constraintEqualToConstant:kItemHeight + kInnerInset * 2],
    ]];

    // 玻璃背景（模糊 + 描边 + 投影）
    [SPGlassMaterial applyTo:_capsule cornerRadius:(kItemHeight + kInnerInset * 2) / 2.0 tint:nil];

    // 液态选中指示（照搬 LiquidGlassKit 的 LiquidLensView）
    // 静止态是半透明白胶囊，按下时变成完整液态玻璃
    _lens = [[SPLiquidLens alloc] initWithFrame:CGRectZero];
    _lens.restingColor = [[UIColor whiteColor] colorWithAlphaComponent:0.20];
    [_capsule addSubview:_lens];

    [self rebuildButtons];
}

- (void)setTitles:(NSArray<NSString *> *)titles { _titles = [titles copy]; [self rebuildButtons]; }
- (void)setSymbols:(NSArray<NSString *> *)symbols { _symbols = [symbols copy]; [self rebuildButtons]; }
- (void)setSelectedSymbols:(NSArray<NSString *> *)selectedSymbols { _selectedSymbols = [selectedSymbols copy]; [self rebuildButtons]; }

- (void)rebuildButtons {
    for (UIButton *b in self.buttons) [b removeFromSuperview];
    [self.buttons removeAllObjects];

    NSUInteger n = MIN(self.titles.count, MIN(self.symbols.count, self.selectedSymbols.count));
    if (n == 0) return;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_capsule addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:_capsule.topAnchor constant:kInnerInset],
        [stack.leadingAnchor constraintEqualToAnchor:_capsule.leadingAnchor constant:kInnerInset],
        [stack.trailingAnchor constraintEqualToAnchor:_capsule.trailingAnchor constant:-kInnerInset],
        [stack.bottomAnchor constraintEqualToAnchor:_capsule.bottomAnchor constant:-kInnerInset],
    ]];

    for (NSUInteger i = 0; i < n; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(tapItem:) forControlEvents:UIControlEventTouchUpInside];

        UIButtonConfiguration *cfg = [UIButtonConfiguration plainConfiguration];
        cfg.imagePlacement = NSDirectionalRectEdgeTop;
        cfg.imagePadding = 3;
        cfg.title = self.titles[i];
        cfg.baseForegroundColor = [SPTheme textDim];
        [cfg setAttributedTitle:[[NSAttributedString alloc]
            initWithString:self.titles[i]
                attributes:@{NSFontAttributeName: [SPTheme scaled:UIFontTextStyleCaption2
                                                           weight:UIFontWeightMedium],
                             NSForegroundColorAttributeName: [SPTheme textDim]}]
                      forState:UIControlStateNormal];
        [cfg setAttributedTitle:[[NSAttributedString alloc]
            initWithString:self.titles[i]
                attributes:@{NSFontAttributeName: [SPTheme scaled:UIFontTextStyleCaption2
                                                           weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName: [SPTheme accent]}]
                      forState:UIControlStateSelected];
        b.configuration = cfg;
        [b setImage:[UIImage systemImageNamed:self.symbols[i]] forState:UIControlStateNormal];
        [b setImage:[UIImage systemImageNamed:self.selectedSymbols[i]] forState:UIControlStateSelected];

        [stack addArrangedSubview:b];
        [self.buttons addObject:b];
    }

    // 透镜放在 stack 下面，避免挡住图标
    [_capsule sendSubviewToBack:_lens];
    [self updateSelection:NO];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)self.buttons.count) return;
    if (_selectedIndex == selectedIndex) return;
    _selectedIndex = selectedIndex;
    [self updateSelection:YES];
}

- (void)tapItem:(UIButton *)sender {
    NSInteger idx = sender.tag;
    [_lens setLifted:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self->_lens setLifted:NO];
    });
    BOOL reselect = (idx == self.selectedIndex);
    self.selectedIndex = idx;
    [SPMotion hapticLight];
    if ([self.delegate respondsToSelector:@selector(floatTabBar:didSelectIndex:)]) {
        [self.delegate floatTabBar:self didSelectIndex:idx];
    }
    if (reselect) SPLog(@"重选 tab %ld", (long)idx);
}

- (void)updateSelection:(BOOL)animated {
    for (UIButton *b in self.buttons) {
        b.selected = (b.tag == self.selectedIndex);
        b.configuration.baseForegroundColor = b.selected ? [SPTheme accent] : [SPTheme textDim];
    }
    [self layoutIfNeeded];
    [self positionLensAnimated:animated];
}

- (CGRect)lensFrameForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.buttons.count) return CGRectZero;
    UIButton *b = self.buttons[index];
    return [b convertRect:b.bounds toView:_capsule];
}

- (void)positionLensAnimated:(BOOL)animated {
    CGRect target = [self lensFrameForIndex:self.selectedIndex];
    if (CGRectIsEmpty(target)) return;
    _lens.targetFrame = target;
    [_lens moveToTargetAnimated:animated];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (CALayer *l in _capsule.layer.sublayers) {
        if ([l.name isEqualToString:@"sp.glass.border"]) l.frame = _capsule.bounds;
    }
    CGRect target = [self lensFrameForIndex:self.selectedIndex];
    if (!CGRectIsEmpty(target)) {
        _lens.targetFrame = target;
        _lens.frame = CGRectInset(target, 4, 4);
    }
}

- (void)setScrolledDown:(BOOL)scrolledDown {
    // 向下滚时略微缩一点，模仿系统 tab bar 收起
    CGFloat scale = scrolledDown ? 0.94 : 1.0;
    CGFloat alpha = scrolledDown ? 0.92 : 1.0;
    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.transform = CGAffineTransformMakeScale(scale, scale);
        self.alpha = alpha;
    } completion:nil];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, kItemHeight + kInnerInset * 2);
}

@end
