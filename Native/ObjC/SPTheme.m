//
//  SPTheme.m
//

#import "SPTheme.h"

#pragma mark - SPMotion（Gasp）

@implementation SPMotion

+ (BOOL)motionAllowed {
    if (@available(iOS 13.0, *)) {
        return !UIAccessibilityIsReduceMotionEnabled();
    }
    return YES;
}

/// Gasp 基础曲线：入场用 easeOut（快起慢收，感觉「利落」）
+ (void)appear:(void (^)(void))animations {
    if (!self.motionAllowed) { if (animations) animations(); return; }
    [UIView animateWithDuration:0.22 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:animations completion:nil];
}

+ (void)disappear:(void (^)(void))animations completion:(void (^)(void))completion {
    if (!self.motionAllowed) {
        if (animations) animations();
        if (completion) completion();
        return;
    }
    [UIView animateWithDuration:0.16 delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:animations completion:^(BOOL finished) { if (completion) completion(); }];
}

/// 弹簧：damping 0.82 不会弹过头，但比线性「有生命感」
+ (void)spring:(void (^)(void))animations {
    if (!self.motionAllowed) { if (animations) animations(); return; }
    [UIView animateWithDuration:0.42 delay:0
         usingSpringWithDamping:0.82 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:animations completion:nil];
}

/// 完成时的「pop」：先放大一点点再回弹，配合触感
+ (void)pop:(UIView *)view {
    if (!view) return;
    if (!self.motionAllowed) return;
    view.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.5 delay:0
         usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ view.transform = CGAffineTransformIdentity; } completion:nil];
}

+ (void)pressDown:(UIView *)view {
    if (!view || !self.motionAllowed) return;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ view.transform = CGAffineTransformMakeScale(0.97, 0.97); } completion:nil];
}

+ (void)pressUp:(UIView *)view {
    if (!view || !self.motionAllowed) return;
    [UIView animateWithDuration:0.28 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ view.transform = CGAffineTransformIdentity; } completion:nil];
}

+ (void)animate:(void (^)(void))animations duration:(NSTimeInterval)duration {
    if (!self.motionAllowed) { if (animations) animations(); return; }
    [UIView animateWithDuration:duration delay:0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:animations completion:nil];
}

+ (void)hapticLight {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Spark.haptics"]) return;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

+ (void)hapticSuccess {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Spark.haptics"]) return;
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}

+ (void)hapticError {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Spark.haptics"]) return;
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeError];
}

@end

#pragma mark - SPTheme

@implementation SPTheme

+ (UIColor *)background     { return [UIColor systemGroupedBackgroundColor]; }
+ (UIColor *)surface        { return [UIColor secondarySystemGroupedBackgroundColor]; }
+ (UIColor *)surfaceHigh    { return [UIColor tertiarySystemGroupedBackgroundColor]; }
+ (UIColor *)separator      { return [UIColor separatorColor]; }
+ (UIColor *)text           { return [UIColor labelColor]; }
+ (UIColor *)textDim        { return [UIColor secondaryLabelColor]; }
+ (UIColor *)accent         { return [UIColor systemBlueColor]; }
+ (UIColor *)success        { return [UIColor systemGreenColor]; }
+ (UIColor *)warn           { return [UIColor systemOrangeColor]; }
+ (UIColor *)danger         { return [UIColor systemRedColor]; }
+ (UIColor *)info           { return [UIColor systemTealColor]; }

+ (UIColor *)codeBackground {
    // 代码区在浅色下用稍暗的底色，深色下用近黑，保证对比度 ≥ 4.5:1
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.09 alpha:1.0]
            : [UIColor colorWithWhite:0.96 alpha:1.0];
    }];
}

+ (UIColor *)codeText {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.92 alpha:1.0]
            : [UIColor colorWithWhite:0.12 alpha:1.0];
    }];
}

/// 日志配色用系统色，深色模式下也不刺眼
+ (UIColor *)colorForLogLevel:(NSInteger)level {
    switch (level) {
        case 1: return [self danger];    // err
        case 2: return [self info];      // info
        case 3: return [self accent];    // step
        default: return [self text];
    }
}

+ (UIFont *)scaled:(UIFontTextStyle)style weight:(UIFontWeight)weight {
    UIFont *base = [UIFont preferredFontForTextStyle:style];
    UIFontDescriptor *d = [base.fontDescriptor fontDescriptorWithSymbolicTraits:
        weight >= UIFontWeightSemibold ? UIFontDescriptorTraitBold : 0];
    if (d) base = [UIFont fontWithDescriptor:d size:base.pointSize];
    return base;
}

+ (UIFont *)title { return [self scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold]; }
+ (UIFont *)body  { return [self scaled:UIFontTextStyleBody weight:UIFontWeightRegular]; }
+ (UIFont *)caption { return [self scaled:UIFontTextStyleCaption1 weight:UIFontWeightRegular]; }

+ (UIFont *)mono:(CGFloat)size {
    return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)mono:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont monospacedSystemFontOfSize:size weight:weight];
}

+ (void)round:(UIView *)view radius:(CGFloat)radius {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
}

+ (void)styleCell:(UITableViewCell *)cell {
    cell.textLabel.textColor = [self text];
    cell.textLabel.font = [self body];
    cell.detailTextLabel.textColor = [self textDim];
    cell.detailTextLabel.font = [self caption];
    cell.backgroundColor = [self surface];
}

+ (void)stylePrimaryButton:(UIButton *)button {
    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.baseBackgroundColor = [self accent];
    cfg.baseForegroundColor = [UIColor whiteColor];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *out = [incoming mutableCopy];
        out[NSFontAttributeName] = [self scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
        return out;
    };
    button.configuration = cfg;
}

+ (void)styleSecondaryButton:(UIButton *)button {
    UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
    cfg.baseBackgroundColor = [[self accent] colorWithAlphaComponent:0.12];
    cfg.baseForegroundColor = [self accent];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    button.configuration = cfg;
}

+ (void)styleDestructiveButton:(UIButton *)button {
    UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
    cfg.baseBackgroundColor = [[self danger] colorWithAlphaComponent:0.12];
    cfg.baseForegroundColor = [self danger];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    button.configuration = cfg;
}

@end

#pragma mark - SPCardView

@implementation SPCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _padding = 14;
        self.backgroundColor = [SPTheme surface];
        [SPTheme round:self radius:SPRadiusM];
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

- (void)setPadding:(CGFloat)padding {
    _padding = padding;
    [self setNeedsLayout];
}

/// 跟随深浅色/描边变化
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    self.backgroundColor = [SPTheme surface];
}

@end

#pragma mark - SPBadgeLabel（HIG 胶囊徽章）

@implementation SPBadgeLabel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.font = [SPTheme scaled:UIFontTextStyleCaption2 weight:UIFontWeightSemibold];
        self.textAlignment = NSTextAlignmentCenter;
        self.layer.borderWidth = 1;
        [SPTheme round:self radius:SPRadiusS];
        self.layer.masksToBounds = YES;
        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}

- (void)setText:(NSString *)text color:(UIColor *)color {
    self.text = text;
    self.textColor = color;
    self.layer.borderColor = [color colorWithAlphaComponent:0.5].CGColor;
    self.backgroundColor = [color colorWithAlphaComponent:0.10];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    // 文字左右留白由 intrinsicContentSize 控制
}

- (CGSize)intrinsicContentSize {
    CGSize s = [super intrinsicContentSize];
    return CGSizeMake(s.width + 14, MAX(s.height, 18));
}

@end

#pragma mark - SPGlassBar

@implementation SPGlassBar

- (instancetype)initWithFrame:(CGRect)frame {
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    if ((self = [super initWithEffect:effect])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

@end

#pragma mark - 设计令牌

const CGFloat SPIconSizeSmall    = 16;
const CGFloat SPIconSizeMedium   = 22;
const CGFloat SPIconSizeLarge    = 28;
const CGFloat SPButtonHeight     = 48;
const CGFloat SPFloatingBarHeight = 60;
const CGFloat SPFloatingBarInset  = 74;
const CGFloat SPFloatingBarSideInset = 28;

@implementation SPMetric
+ (CGFloat)pageMargin { return SPSpaceM; }
+ (CGFloat)sectionGap { return SPSpaceL; }
+ (CGFloat)inlineGap  { return SPSpaceXS; }
@end
