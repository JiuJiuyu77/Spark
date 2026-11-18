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
#import "SPCompat.h"

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

    blur.clipsToBounds = YES;
    blur.layer.cornerRadius = radius;
    blur.layer.cornerCurve = kCACornerCurveContinuous;

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
    CALayer *border = [self specularBorderForBounds:view.bounds cornerRadius:radius];
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

#pragma mark - SPGlassHeaderView

@interface SPGlassHeaderView ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation SPGlassHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithRadius:SPRadiusL])) {
        self.showsGlare = YES;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
        _titleLabel.textColor = [SPTheme text];
        _titleLabel.numberOfLines = 1;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightRegular];
        _subtitleLabel.textColor = [SPTheme textDim];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:SPSpaceM],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:SPIconSizeLarge + 6],
            [_iconView.heightAnchor constraintEqualToConstant:SPIconSizeLarge + 6],

            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:SPSpaceM],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:SPSpaceS],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-SPSpaceM],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:SPSpaceXXS],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-SPSpaceM],
        ]];
    }
    return self;
}

- (void)configureWithSymbol:(NSString *)symbol
                      title:(NSString *)title
                   subtitle:(NSString *)subtitle
                      tint:(UIColor *)tint {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:SPIconSizeLarge - 4
                                                        weight:UIImageSymbolWeightSemibold];
    self.iconView.image = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    self.iconView.tintColor = tint ?: [SPTheme accent];
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = !subtitle.length;
}

@end

#pragma mark - SPGlassButton

@interface SPGlassButton ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;
@end

@implementation SPGlassButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit];
    }
    return self;
}

+ (instancetype)buttonWithTitle:(NSString *)title
                         symbol:(NSString *)symbol
                          style:(SPGlassButtonStyle)style {
    SPGlassButton *b = [[SPGlassButton alloc] initWithFrame:CGRectZero];
    b.title = title;
    b.symbol = symbol;
    b.style = style;
    [b rebuild];
    return b;
}

- (void)commonInit {
    _style = SPGlassButtonStyleProminent;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _iconView = [[UIImageView alloc] init];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.userInteractionEnabled = NO;
    [self addSubview:_iconView];

    _label = [[UILabel alloc] init];
    _label.font = [SPTheme scaled:UIFontTextStyleCallout weight:UIFontWeightSemibold];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:SPButtonHeight],
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:SPSpaceM],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:SPIconSizeSmall],
        [_iconView.heightAnchor constraintEqualToConstant:SPIconSizeSmall],
        [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:SPSpaceXS],
        [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-SPSpaceM],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];

    [self addTarget:self action:@selector(handleTouchDown) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(handleTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

- (void)setTitle:(NSString *)title { _title = [title copy]; [self rebuild]; }
- (void)setSymbol:(NSString *)symbol { _symbol = [symbol copy]; [self rebuild]; }
- (void)setStyle:(SPGlassButtonStyle)style { _style = style; [self rebuild]; }

- (void)rebuild {
    if (!self.label) return;   // 还没初始化完
    self.label.text = self.title;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:SPIconSizeSmall - 2
                                                        weight:UIImageSymbolWeightSemibold];
    self.iconView.image = self.symbol.length ? [UIImage systemImageNamed:self.symbol withConfiguration:cfg] : nil;
    self.iconView.hidden = !self.symbol.length;

    BOOL prominent = (self.style == SPGlassButtonStyleProminent);
    self.label.textColor = prominent ? [SPTheme accent] : [SPTheme text];
    self.iconView.tintColor = prominent ? [SPTheme accent] : [SPTheme textDim];

    // 背景：主操作用淡色调玻璃，次要用中性
    UIColor *tint = prominent
        ? [[SPTheme accent] colorWithAlphaComponent:0.16]
        : [[UIColor whiteColor] colorWithAlphaComponent:0.10];
    self.tintColor = tint;
}

- (void)handleTouchDown {
    [SPMotion pressDown:self];
    [SPMotion hapticLight];
}

- (void)handleTouchUp {
    [SPMotion pressUp:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = SPRadiusM;
    if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (CGRectContainsPoint(self.bounds, [touches.anyObject locationInView:self])) {
        if (self.onTap) self.onTap();
    }
}

@end

#pragma mark - SPGlassPill

@implementation SPGlassPill

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithRadius:SPRadiusS])) {
        self.showsGlare = NO;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    [self setNeedsDisplay];
    [self setNeedsLayout];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    UIFont *font = [SPTheme scaled:UIFontTextStyleCaption2 weight:UIFontWeightSemibold];
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: self.tintColor ?: [SPTheme textDim],
    };
    CGSize size = [self.text sizeWithAttributes:attrs];
    [self.text drawAtPoint:CGPointMake((CGRectGetWidth(rect) - size.width) / 2,
                                       (CGRectGetHeight(rect) - size.height) / 2)
            withAttributes:attrs];
}

- (CGSize)intrinsicContentSize {
    UIFont *font = [SPTheme scaled:UIFontTextStyleCaption2 weight:UIFontWeightSemibold];
    CGSize size = [(self.text ?: @"") sizeWithAttributes:@{NSFontAttributeName: font}];
    return CGSizeMake(size.width + SPSpaceS * 2, size.height + SPSpaceXXS * 2);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
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

static CGFloat const kItemHeight = 54;   // 与 SPFloatingBarHeight(60) 配合：54 + 3*2 = 60
static CGFloat const kInnerInset = 3;    // 参考 TabBar 的 innerInset（略收紧）

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

        // 用传统 API 而不是 UIButtonConfiguration：
        // configuration 不支持按 state 设不同标题，选中态变色很别扭。
        // 这里用 setAttributedTitle:forState: 直接控制字体与颜色，
        // 图标的选中态用 setImage:forState:。
        b.titleLabel.textAlignment = NSTextAlignmentCenter;

        NSAttributedString *normal = [[NSAttributedString alloc]
            initWithString:self.titles[i]
                attributes:@{
                    NSFontAttributeName: [SPTheme scaled:UIFontTextStyleCaption2
                                                  weight:UIFontWeightMedium],
                    NSForegroundColorAttributeName: [SPTheme textDim],
                }];
        NSAttributedString *selected = [[NSAttributedString alloc]
            initWithString:self.titles[i]
                attributes:@{
                    NSFontAttributeName: [SPTheme scaled:UIFontTextStyleCaption2
                                                  weight:UIFontWeightSemibold],
                    NSForegroundColorAttributeName: [SPTheme accent],
                }];
        [b setAttributedTitle:normal forState:UIControlStateNormal];
        [b setAttributedTitle:selected forState:UIControlStateSelected];
        [b setAttributedTitle:selected forState:UIControlStateSelected | UIControlStateHighlighted];

        UIImageSymbolConfiguration *icfg =
            [UIImageSymbolConfiguration configurationWithPointSize:SPIconSizeMedium - 6
                                                            weight:UIImageSymbolWeightRegular];
        [b setImage:[UIImage systemImageNamed:self.symbols[i] withConfiguration:icfg]
            forState:UIControlStateNormal];
        [b setImage:[UIImage systemImageNamed:self.selectedSymbols[i] withConfiguration:icfg]
            forState:UIControlStateSelected];

        // 图标在上、文字在下
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        // 图标在上、文字在下；偏移量按 60pt 高度调过，
        // 之前用 -8/10/22 会让文字压到胶囊底部
        b.imageEdgeInsets = UIEdgeInsetsMake(-6, 0, 8, 0);
        b.titleEdgeInsets = UIEdgeInsetsMake(18, 0, -18, 0);

        [stack addArrangedSubview:b];
        [self.buttons addObject:b];
    }

    // 透镜放在 stack 下面，避免挡住图标
    // lens 必须在背景上面、按钮下面，不能送到模糊层后面。
    [_capsule insertSubview:_lens belowSubview:stack];
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
        if ([l.name isEqualToString:@"sp.glass.border"]) {
            l.frame = _capsule.bounds;
            ((CAShapeLayer *)l).path = [UIBezierPath bezierPathWithRoundedRect:_capsule.bounds cornerRadius:CGRectGetHeight(_capsule.bounds)/2].CGPath;
        }
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


#pragma mark - 表格头部容器
//
// tableHeaderView 的宽度不会自动跟随表格，必须自己在 layoutSubviews
// 里重新测一次。包一层容器是最稳妥的做法。

@interface SPHeaderContainer : UIView
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong, nullable) UIColor *tint;
@property (nonatomic, weak) SPGlassHeaderView *inner;
@property (nonatomic, assign) CGFloat lastWidth;
@end

@implementation SPHeaderContainer

- (instancetype)initWithSymbol:(NSString *)symbol
                         title:(NSString *)title
                      subtitle:(NSString *)subtitle
                          tint:(UIColor *)tint {
    if ((self = [super initWithFrame:CGRectZero])) {
        _symbol = [symbol copy];
        _title = [title copy];
        _subtitle = [subtitle copy];
        _tint = tint;
        self.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)relayoutForWidth:(CGFloat)width {
    if (width <= 0 || fabs(width - self.lastWidth) < 0.5) return;
    self.lastWidth = width;

    [self.inner removeFromSuperview];
    SPGlassHeaderView *h = [[SPGlassHeaderView alloc] initWithFrame:CGRectMake(0, 0, width, 96)];
    [h configureWithSymbol:self.symbol ?: @"circle"
                     title:self.title ?: @""
                  subtitle:self.subtitle
                      tint:self.tint];
    CGSize sz = [h systemLayoutSizeFittingSize:CGSizeMake(width, UIViewNoIntrinsicMetric)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    h.frame = CGRectMake(0, 0, width, MAX(96, sz.height));
    [self addSubview:h];
    self.inner = h;

    CGRect f = self.frame;
    f.size = CGSizeMake(width, h.frame.size.height);
    self.frame = f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self relayoutForWidth:self.bounds.size.width];
}

@end

#pragma mark - 表格头部工厂

UIView *SPTableHeader(NSString *symbol, NSString *title, NSString *subtitle,
                      UIColor *tint, CGFloat width) {
    // width 只是首帧估值。
    // tableHeaderView 不会自动跟随表格宽度，写死 320 在 iPad / 横屏下
    // 会明显偏窄（右侧留一大块空白）。这里包一层容器，
    // 由它在 layoutSubviews 里按真实宽度重建。
    SPHeaderContainer *c = [[SPHeaderContainer alloc] initWithSymbol:symbol
                                                               title:title
                                                            subtitle:subtitle
                                                                tint:tint];
    c.frame = CGRectMake(0, 0, width, 96);
    [c relayoutForWidth:width];
    return c;
}

@end
