//
//  RBTheme.m
//

#import "RBTheme.h"

@implementation RBTheme

#define RBCOLOR(rgb) [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 \
                                     green:((rgb >> 8) & 0xFF) / 255.0 \
                                      blue:(rgb & 0xFF) / 255.0 alpha:1.0]

+ (UIColor *)background     { return RBCOLOR(0x0E1116); }
+ (UIColor *)surface        { return RBCOLOR(0x151A21); }
+ (UIColor *)surfaceHigh    { return RBCOLOR(0x1D242E); }
+ (UIColor *)separator      { return RBCOLOR(0x262E3A); }
+ (UIColor *)text           { return RBCOLOR(0xE6EDF3); }
+ (UIColor *)textDim        { return RBCOLOR(0x8B98A9); }
+ (UIColor *)accent         { return RBCOLOR(0x35D6A4); }
+ (UIColor *)accentDim      { return RBCOLOR(0x1F8F6E); }
+ (UIColor *)warn           { return RBCOLOR(0xF2B73D); }
+ (UIColor *)danger         { return RBCOLOR(0xFF5C68); }
+ (UIColor *)info           { return RBCOLOR(0x58A6FF); }
+ (UIColor *)codeBackground  { return RBCOLOR(0x0B0E12); }

+ (UIFont *)monoFont:(CGFloat)size {
    return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)monoFont:(CGFloat)size bold:(BOOL)bold {
    return [UIFont monospacedSystemFontOfSize:size weight:bold ? UIFontWeightSemibold : UIFontWeightRegular];
}

+ (UIFont *)uiFont:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont systemFontOfSize:size weight:weight];
}

+ (void)styleCard:(UIView *)view {
    view.backgroundColor = [self surface];
    view.layer.cornerRadius = 14;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 0.5;
    view.layer.borderColor = [self separator].CGColor;
}

+ (void)stylePrimaryButton:(UIButton *)button {
    button.backgroundColor = [self accent];
    [button setTitleColor:[UIColor colorWithWhite:0.05 alpha:1] forState:UIControlStateNormal];
    button.titleLabel.font = [self uiFont:15 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 11;
    button.layer.cornerCurve = kCACornerCurveContinuous;
}

+ (void)styleSecondaryButton:(UIButton *)button {
    button.backgroundColor = [self surfaceHigh];
    [button setTitleColor:[self text] forState:UIControlStateNormal];
    button.titleLabel.font = [self uiFont:14 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 11;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [self separator].CGColor;
}

+ (void)styleDangerButton:(UIButton *)button {
    button.backgroundColor = [[self danger] colorWithAlphaComponent:0.16];
    [button setTitleColor:[self danger] forState:UIControlStateNormal];
    button.titleLabel.font = [self uiFont:14 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 11;
    button.layer.cornerCurve = kCACornerCurveContinuous;
}

+ (CAGradientLayer *)accentGradientForBounds:(CGRect)bounds {
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = bounds;
    g.colors = @[(id)[self accent].CGColor, (id)[self info].CGColor];
    g.startPoint = CGPointMake(0, 0.5);
    g.endPoint = CGPointMake(1, 0.5);
    return g;
}

+ (UIColor *)colorForLogLevel:(NSInteger)level {
    switch (level) {
        case 1: return [self danger];   // err
        case 2: return [self info];     // info
        case 3: return [self accent];   // step
        default: return [self text];
    }
}

@end

#pragma mark - RBCardView

@implementation RBCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [RBTheme styleCard:self];
        _contentView = [[UIView alloc] init];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_contentView];
        [NSLayoutConstraint activateConstraints:@[
            [_contentView.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
        ]];
    }
    return self;
}

@end

#pragma mark - RBBadgeLabel

@implementation RBBadgeLabel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.font = [RBTheme uiFont:11 weight:UIFontWeightSemibold];
        self.textAlignment = NSTextAlignmentCenter;
        self.layer.cornerRadius = 6;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}

- (void)setText:(NSString *)text color:(UIColor *)color {
    self.text = [NSString stringWithFormat:@" %@ ", text];
    self.textColor = color;
    self.backgroundColor = [color colorWithAlphaComponent:0.15];
}

@end
