//
//  SPGlassKit.m
//

#import "SPGlassKit.h"
#import "SPTheme.h"

#pragma mark - SPGlassMaterial

@implementation SPGlassMaterial

+ (void)applyTo:(UIView *)view cornerRadius:(CGFloat)radius tint:(UIColor *)tint {
    static const NSInteger kBlurTag = 0x6C6179;   // 'glay'
    static const NSInteger kTintTag = 0x74696E74; // 'tint'
    static const NSInteger kBorderTag = 0x626F7264;

    [[view viewWithTag:kBlurTag] removeFromSuperview];
    [[view viewWithTag:kTintTag] removeFromSuperview];
    [[view viewWithTag:kBorderTag].layer removeFromSuperlayer];

    // 1) 模糊层：系统厚材质，深浅色自动适配
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    blur.tag = kBlurTag;
    blur.userInteractionEnabled = NO;
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    [view insertSubview:blur atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:view.topAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];

    // 2) 色调层：给玻璃一点「自己的颜色」，避免纯灰
    UIColor *t = tint ?: [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.06]
            : [UIColor colorWithWhite:1.0 alpha:0.55];
    }];
    UIView *tintView = [[UIView alloc] init];
    tintView.tag = kTintTag;
    tintView.userInteractionEnabled = NO;
    tintView.backgroundColor = t;
    tintView.translatesAutoresizingMaskIntoConstraints = NO;
    [view insertSubview:tintView aboveSubview:blur];
    [NSLayoutConstraint activateConstraints:@[
        [tintView.topAnchor constraintEqualToAnchor:view.topAnchor],
        [tintView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [tintView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [tintView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];

    // 3) 折射高光：上亮下暗的描边
    // 先移除旧的描边/高光，避免每次 layout 叠加
    for (CALayer *l in [view.layer.sublayers copy]) {
        if ([l.name isEqualToString:@"sp.glass.border"] ||
            [l.name isEqualToString:@"sp.glass.highlight"]) [l removeFromSuperlayer];
    }
    CAGradientLayer *highlight = [self specularHighlightForBounds:view.bounds cornerRadius:radius];
    [view.layer addSublayer:highlight];
    CALayer *border = [self specularBorderForBounds:view.bounds cornerRadius:radius];
    [view.layer addSublayer:border];

    view.clipsToBounds = NO;
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;

    // 4) 外投影：让玻璃「浮」起来
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.18;
    view.layer.shadowRadius = 18;
    view.layer.shadowOffset = CGSizeMake(0, 8);
    view.layer.masksToBounds = NO;
}

/// 玻璃描边：用 CAShapeLayer 描一圈，颜色随深浅色切换
/// （CAGradientLayer 没有 strokeColor，所以这里单独用形状层）
+ (CALayer *)specularBorderForBounds:(CGRect)bounds cornerRadius:(CGFloat)radius {
    CAShapeLayer *border = [CAShapeLayer layer];
    border.name = @"sp.glass.border";
    border.frame = bounds;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 0.5, 0.5)
                                                    cornerRadius:radius];
    border.path = path.CGPath;
    border.fillColor = UIColor.clearColor.CGColor;
    border.lineWidth = 1.0;

    BOOL dark = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    border.strokeColor = dark
        ? [UIColor colorWithWhite:1.0 alpha:0.28].CGColor
        : [UIColor colorWithWhite:0.0 alpha:0.07].CGColor;
    return border;
}

/// 玻璃内部的高光渐变（上亮下暗），单独一层铺在模糊层之上
+ (CAGradientLayer *)specularHighlightForBounds:(CGRect)bounds cornerRadius:(CGFloat)radius {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.name = @"sp.glass.highlight";
    g.frame = bounds;
    g.cornerRadius = radius;
    if (@available(iOS 13.0, *)) g.cornerCurve = kCACornerCurveContinuous;

    BOOL dark = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    if (dark) {
        g.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor,
            (id)[UIColor clearColor].CGColor,
        ];
    } else {
        g.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.65].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
            (id)[UIColor clearColor].CGColor,
        ];
    }
    g.locations = @[@0.0, @0.45, @1.0];
    g.startPoint = CGPointMake(0.5, 0.0);
    g.endPoint = CGPointMake(0.5, 1.0);
    return g;
}

@end

#pragma mark - SPGlassCard

@interface SPGlassCard ()
@property (nonatomic, strong) UIView *pressedOverlay;
@end

@implementation SPGlassCard

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _padding = 14;
        _cornerRadius = 20;
        self.backgroundColor = UIColor.clearColor;

        _contentView = [[UIView alloc] init];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_contentView];
        [NSLayoutConstraint activateConstraints:@[
            [_contentView.topAnchor constraintEqualToAnchor:self.topAnchor constant:_padding],
            [_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_padding],
            [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-_padding],
            [_contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-_padding],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [SPGlassMaterial applyTo:self cornerRadius:self.cornerRadius tint:nil];
}

- (void)press {
    [SPMotion pressDown:self];
}

- (void)releasePressed {
    [SPMotion pressUp:self];
}

@end

#pragma mark - SPFloatTabBar

@interface SPFloatTabButton : UIView
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *selectedSymbolName;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *glow;
@property (nonatomic, assign) BOOL selected;
@end

@implementation SPFloatTabButton

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol selectedSymbol:(NSString *)sel {
    if ((self = [super init])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _glow = [[UIView alloc] init];
        _glow.translatesAutoresizingMaskIntoConstraints = NO;
        _glow.backgroundColor = [SPTheme accent];
        _glow.alpha = 0;
        _glow.layer.cornerRadius = 18;
        [self addSubview:_glow];

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [SPTheme scaled:UIFontTextStyleCaption2 weight:UIFontWeightMedium];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_glow.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_glow.centerYAnchor constraintEqualToAnchor:self.iconView.centerYAnchor],
            [_glow.widthAnchor constraintEqualToConstant:44],
            [_glow.heightAnchor constraintEqualToConstant:30],

            [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:24],
            [_iconView.heightAnchor constraintEqualToConstant:24],

            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:2],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        ]];
        self.symbolName = symbol;
        self.selectedSymbolName = sel;
        self.selected = NO;
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.iconView.image = [UIImage systemImageNamed:(selected ? self.selectedSymbolName : self.symbolName)];
    self.iconView.tintColor = selected ? [SPTheme accent] : [SPTheme textDim];
    self.titleLabel.textColor = selected ? [SPTheme accent] : [SPTheme textDim];
    [SPMotion spring:^{
        self.glow.alpha = selected ? 0.16 : 0.0;
        self.iconView.transform = selected ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
    }];
}

@end

@interface SPFloatTabBar ()
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) NSMutableArray<SPFloatTabButton *> *buttons;
@property (nonatomic, strong) UIView *indicator;
@property (nonatomic, assign) BOOL scrolledDown;
@end

@implementation SPFloatTabBar

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles
                       symbols:(NSArray<NSString *> *)symbols
               selectedSymbols:(NSArray<NSString *> *)selectedSymbols {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.titles = titles;
        self.symbols = symbols;
        self.selectedSymbols = selectedSymbols;
        _buttons = [NSMutableArray array];
        [self build];
    }
    return self;
}

- (void)build {
    self.backgroundColor = UIColor.clearColor;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.container = [[UIView alloc] init];
    self.container.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.container];
    [NSLayoutConstraint activateConstraints:@[
        [self.container.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.container.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.container.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.container.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.heightAnchor constraintEqualToConstant:64],
    ]];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.container.topAnchor constant:4],
        [stack.leadingAnchor constraintEqualToAnchor:self.container.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:self.container.trailingAnchor constant:-10],
        [stack.bottomAnchor constraintEqualToAnchor:self.container.bottomAnchor constant:-4],
    ]];

    for (NSInteger i = 0; i < (NSInteger)self.titles.count; i++) {
        SPFloatTabButton *b = [[SPFloatTabButton alloc] initWithTitle:self.titles[i]
                                                               symbol:self.symbols[i]
                                                       selectedSymbol:self.selectedSymbols[i]];
        b.tag = 7000 + i;
        [b addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
        [stack addArrangedSubview:b];
        [self.buttons addObject:b];
    }
    self.selectedIndex = 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [SPGlassMaterial applyTo:self.container cornerRadius:32 tint:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    // 深浅色切换：玻璃描边与色调都要重算
    [SPGlassMaterial applyTo:self.container cornerRadius:32 tint:nil];
    for (SPFloatTabButton *b in self.buttons) {
        b.selected = b.selected;   // 触发颜色刷新
    }
}

- (void)tapped:(UITapGestureRecognizer *)g {
    NSInteger idx = g.view.tag - 7000;
    if (idx < 0 || idx >= (NSInteger)self.buttons.count) return;
    [self setSelectedIndex:idx];
    [SPMotion hapticLight];
    if ([self.delegate respondsToSelector:@selector(floatTabBar:didSelectIndex:)]) {
        [self.delegate floatTabBar:self didSelectIndex:idx];
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    for (NSInteger i = 0; i < (NSInteger)self.buttons.count; i++) {
        self.buttons[i].selected = (i == selectedIndex);
    }
}

- (void)setScrolledDown:(BOOL)scrolledDown {
    if (_scrolledDown == scrolledDown) return;
    _scrolledDown = scrolledDown;
    [SPMotion animate:^{
        self.transform = scrolledDown
            ? CGAffineTransformMakeScale(0.94, 0.94)
            : CGAffineTransformIdentity;
        self.alpha = scrolledDown ? 0.92 : 1.0;
    } duration:0.22];
}

@end
