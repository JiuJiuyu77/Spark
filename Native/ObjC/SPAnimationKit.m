//
//  SPAnimationKit.m
//

#import "SPAnimationKit.h"
#import "SPTheme.h"

static const NSInteger kSkeletonTag = 0x736B656C;    // 'skel'

@implementation SPAnimationKit

+ (BOOL)motionAllowed { return [SPMotion motionAllowed]; }

#pragma mark - 交错入场

+ (void)stagger:(NSArray<UIView *> *)views offset:(CGFloat)offset {
    if (!views.count) return;
    if (![self motionAllowed]) {
        for (UIView *v in views) { v.alpha = 1; v.transform = CGAffineTransformIdentity; }
        return;
    }
    for (NSInteger i = 0; i < (NSInteger)views.count; i++) {
        UIView *v = views[i];
        v.alpha = 0;
        v.transform = CGAffineTransformMakeTranslation(0, offset);
    }
    for (NSInteger i = 0; i < (NSInteger)views.count; i++) {
        UIView *v = views[i];
        [UIView animateWithDuration:0.42
                              delay:0.045 * i
             usingSpringWithDamping:0.86
              initialSpringVelocity:0.3
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            v.alpha = 1;
            v.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

#pragma mark - 涟漪

+ (void)rippleIn:(UIView *)view at:(CGPoint)point color:(UIColor *)color {
    if (!view || ![self motionAllowed]) return;
    UIColor *c = color ?: [[SPTheme accent] colorWithAlphaComponent:0.22];

    // 找一个足够覆盖整个视图的半径
    CGFloat r = 0;
    CGSize sz = view.bounds.size;
    NSArray<NSValue *> *corners = @[
        [NSValue valueWithCGPoint:CGPointZero],
        [NSValue valueWithCGPoint:CGPointMake(sz.width, 0)],
        [NSValue valueWithCGPoint:CGPointMake(0, sz.height)],
        [NSValue valueWithCGPoint:CGPointMake(sz.width, sz.height)],
    ];
    for (NSValue *v in corners) {
        CGPoint q = v.CGPointValue;
        CGFloat d = hypot(q.x - point.x, q.y - point.y);
        r = MAX(r, d);
    }

    UIView *ripple = [[UIView alloc] initWithFrame:CGRectMake(point.x - 1, point.y - 1, 2, 2)];
    ripple.backgroundColor = c;
    ripple.layer.cornerRadius = 1;
    ripple.userInteractionEnabled = NO;
    [view addSubview:ripple];

    [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        ripple.transform = CGAffineTransformMakeScale(r, r);
        ripple.alpha = 0;
    } completion:^(BOOL finished) {
        [ripple removeFromSuperview];
    }];
}

#pragma mark - 呼吸光晕

+ (CALayer *)breatheGlowOn:(UIView *)view color:(UIColor *)color {
    if (!view) return nil;
    for (CALayer *l in [view.layer.sublayers copy]) {
        if ([l.name isEqualToString:@"sp.breatheGlow"]) [l removeFromSuperlayer];
    }
    CALayer *glow = [CALayer layer];
    glow.name = @"sp.breatheGlow";
    glow.frame = view.bounds;
    glow.cornerRadius = view.layer.cornerRadius;
    glow.backgroundColor = [color colorWithAlphaComponent:0.16].CGColor;
    glow.opacity = 0.0;
    [view.layer insertSublayer:glow atIndex:0];

    if (![self motionAllowed]) { glow.opacity = 0.6; return glow; }

    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @0.15;
    a.toValue = @0.55;
    a.duration = 1.4;
    a.autoreverses = YES;
    a.repeatCount = HUGE_VALF;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [glow addAnimation:a forKey:@"breathe"];
    return glow;
}

#pragma mark - 数字滚动

+ (void)animateNumberLabel:(UILabel *)label from:(NSInteger)from to:(NSInteger)to
                     format:(NSString *(^)(NSInteger))format {
    if (!label) return;
    NSString *(^fmt)(NSInteger) = format ?: ^NSString *(NSInteger v) {
        return [NSString stringWithFormat:@"%ld", (long)v];
    };
    if (![self motionAllowed] || from == to) {
        label.text = fmt(to);
        return;
    }
    // 分 6 帧插值 + easeOut，视觉上接近连续滚动
    NSInteger start = from;
    NSTimeInterval duration = 0.35;
    NSInteger steps = 6;
    for (NSInteger i = 1; i <= steps; i++) {
        float t = (float)i / (float)steps;
        // easeOut
        float eased = 1.0f - powf(1.0f - t, 3.0f);
        NSInteger v = (NSInteger)llround((double)start + ((double)to - (double)start) * eased);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * t * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            label.text = fmt(v);
        });
    }
}

#pragma mark - 底部弹起

+ (void)springInFromBottom:(UIView *)view completion:(void (^)(void))completion {
    if (!view) return;
    if (![self motionAllowed]) {
        view.alpha = 1;
        view.transform = CGAffineTransformIdentity;
        if (completion) completion();
        return;
    }
    view.alpha = 0;
    view.transform = CGAffineTransformMakeTranslation(0, 40);
    [UIView animateWithDuration:0.46 delay:0
         usingSpringWithDamping:0.78 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.alpha = 1;
        view.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) { if (completion) completion(); }];
}

+ (void)springOutToBottom:(UIView *)view completion:(void (^)(void))completion {
    if (!view) return;
    [UIView animateWithDuration:0.24 delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        view.alpha = 0;
        view.transform = CGAffineTransformMakeTranslation(0, 24);
    } completion:^(BOOL finished) {
        view.transform = CGAffineTransformIdentity;
        if (completion) completion();
    }];
}

#pragma mark - 骨架屏

+ (void)skeletonize:(UIView *)view {
    if (!view || [view viewWithTag:kSkeletonTag]) return;
    UIView *sk = [[UIView alloc] initWithFrame:view.bounds];
    sk.tag = kSkeletonTag;
    sk.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sk.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.07]
            : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
    sk.layer.cornerRadius = view.layer.cornerRadius;
    sk.userInteractionEnabled = NO;
    [view addSubview:sk];

    if (![self motionAllowed]) return;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @0.45;
    a.toValue = @1.0;
    a.duration = 1.1;
    a.autoreverses = YES;
    a.repeatCount = HUGE_VALF;
    [sk.layer addAnimation:a forKey:@"skeleton"];
}

+ (void)deskeletonize:(UIView *)view {
    [[view viewWithTag:kSkeletonTag] removeFromSuperview];
}

@end

#pragma mark - SPRingProgressView

@interface SPRingProgressView ()
@property (nonatomic, strong) CAShapeLayer *track;
@property (nonatomic, strong) CAShapeLayer *arc;
@end

@implementation SPRingProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _lineWidth = 6;
        _progressColor = [SPTheme accent];
        _progress = 0;
        self.backgroundColor = UIColor.clearColor;

        _track = [CAShapeLayer layer];
        _track.fillColor = UIColor.clearColor.CGColor;
        _track.strokeColor = [[SPTheme separator] colorWithAlphaComponent:0.6].CGColor;
        _track.lineWidth = _lineWidth;
        _track.lineCap = kCALineCapRound;
        [self.layer addSublayer:_track];

        _arc = [CAShapeLayer layer];
        _arc.fillColor = UIColor.clearColor.CGColor;
        _arc.strokeColor = _progressColor.CGColor;
        _arc.lineWidth = _lineWidth;
        _arc.lineCap = kCALineCapRound;
        _arc.strokeEnd = 0;
        [self.layer addSublayer:_arc];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inset = self.lineWidth / 2 + 1;
    CGRect r = CGRectInset(self.bounds, inset, inset);
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:r];
    self.track.path = circle.CGPath;
    self.arc.path = circle.CGPath;
    // 从 12 点开始顺时针
    self.track.transform = CATransform3DMakeRotation(-M_PI_2, 0, 0, 1);
    self.arc.transform = self.track.transform;
}

- (void)setProgressColor:(UIColor *)progressColor {
    _progressColor = progressColor;
    self.arc.strokeColor = progressColor.CGColor;
}

- (void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = lineWidth;
    self.track.lineWidth = lineWidth;
    self.arc.lineWidth = lineWidth;
    [self setNeedsLayout];
}

- (void)setProgress:(CGFloat)progress {
    [self setProgress:progress animated:NO];
}

- (void)setProgress:(CGFloat)progress animated:(BOOL)animated {
    _progress = MAX(0, MIN(1, progress));
    if (animated && [SPMotion motionAllowed]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        a.fromValue = @(self.arc.strokeEnd);
        a.toValue = @(_progress);
        a.duration = 0.35;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.arc.strokeEnd = _progress;
        [self.arc addAnimation:a forKey:@"strokeEnd"];
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.arc.strokeEnd = _progress;
        [CATransaction commit];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    self.track.strokeColor = [[SPTheme separator] colorWithAlphaComponent:0.6].CGColor;
    self.arc.strokeColor = self.progressColor.CGColor;
}

@end
