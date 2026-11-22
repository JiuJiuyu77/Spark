//
//  SPHealthDetailViewController.m
//  单项检查的详情：结论 / 为什么怎么办 / 命令 / 原始输出
//

#import "SPHealthDetailViewController.h"
#import "SPHealthCheck.h"
#import "SPTheme.h"
#import "SPCompat.h"

@implementation SPHealthDetailViewController

- (instancetype)initWithItem:(SPHealthItem *)item {
    self = [super initWithNibName:nil bundle:nil];
    if (self) _item = item;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.item.title;
    self.view.backgroundColor = [SPTheme background];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = SPSpaceM;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:SPSpaceM],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:SPSpaceM],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-SPSpaceM],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-SPSpaceL],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-SPSpaceM * 2],
    ]];

    NSString *statusText = @"通过";
    UIColor *statusColor = [SPTheme success];
    if (self.item.status == SPHealthStatusFail) { statusText = @"未通过"; statusColor = [SPTheme danger]; }
    else if (self.item.status == SPHealthStatusWarn) { statusText = @"警告"; statusColor = [SPTheme warn]; }
    else if (self.item.status == SPHealthStatusSkip) { statusText = @"跳过"; statusColor = [SPTheme textDim]; }

    [stack addArrangedSubview:[self labelWithText:statusText
                                            font:[SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold]
                                           color:statusColor]];

    if (self.item.summary.length) {
        [stack addArrangedSubview:[self labelWithText:self.item.summary
                                                font:[SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightRegular]
                                               color:[SPTheme text]]];
    }

    if (self.item.diagnosis.length) {
        [stack addArrangedSubview:[self sectionTitle:@"为什么 / 怎么办"]];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [statusColor colorWithAlphaComponent:0.10];
        card.layer.cornerRadius = SPRadiusM;
        card.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *l = [[UILabel alloc] init];
        l.text = self.item.diagnosis;
        l.numberOfLines = 0;
        l.font = [SPTheme scaled:UIFontTextStyleSubheadline weight:UIFontWeightRegular];
        l.textColor = [SPTheme text];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [l.topAnchor constraintEqualToAnchor:card.topAnchor constant:SPSpaceM],
            [l.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:SPSpaceM],
            [l.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-SPSpaceM],
            [l.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-SPSpaceM],
        ]];
        [stack addArrangedSubview:card];
    }

    if (self.item.command.length) {
        [stack addArrangedSubview:[self sectionTitle:@"执行的命令"]];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [SPTheme surface];
        card.layer.cornerRadius = SPRadiusM;
        card.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *l = [[UILabel alloc] init];
        l.text = self.item.command;
        l.numberOfLines = 0;
        l.font = [SPTheme mono:12];
        l.textColor = [SPTheme codeText];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:l];

        UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
        [copy setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        copy.translatesAutoresizingMaskIntoConstraints = NO;
        copy.accessibilityLabel = @"复制命令";
        [copy addTarget:self action:@selector(copyCommand) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:copy];

        [NSLayoutConstraint activateConstraints:@[
            [l.topAnchor constraintEqualToAnchor:card.topAnchor constant:SPSpaceM],
            [l.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:SPSpaceM],
            [l.trailingAnchor constraintEqualToAnchor:copy.leadingAnchor constant:-SPSpaceS],
            [l.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-SPSpaceM],

            [copy.topAnchor constraintEqualToAnchor:card.topAnchor constant:SPSpaceS],
            [copy.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-SPSpaceS],
            [copy.widthAnchor constraintEqualToConstant:36],
            [copy.heightAnchor constraintEqualToConstant:36],
        ]];
        [stack addArrangedSubview:card];
    }

    if (self.item.output.length) {
        [stack addArrangedSubview:[self sectionTitle:@"原始输出"]];

        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [SPTheme surface];
        card.layer.cornerRadius = SPRadiusM;
        card.translatesAutoresizingMaskIntoConstraints = NO;

        UITextView *tv = [[UITextView alloc] init];
        tv.text = self.item.output;
        tv.font = [SPTheme mono:11];
        tv.textColor = [SPTheme text];
        tv.backgroundColor = [UIColor clearColor];
        tv.editable = NO;
        tv.scrollEnabled = NO;
        tv.textContainerInset = UIEdgeInsetsZero;
        tv.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:tv];
        [NSLayoutConstraint activateConstraints:@[
            [tv.topAnchor constraintEqualToAnchor:card.topAnchor constant:SPSpaceM],
            [tv.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:SPSpaceM],
            [tv.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-SPSpaceM],
            [tv.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-SPSpaceM],
        ]];
        [stack addArrangedSubview:card];
    }

    if (self.item.command.length) {
        UILabel *meta = [self labelWithText:[NSString stringWithFormat:@"退出码 %ld · 耗时 %ld ms",
                                             (long)self.item.exitCode, (long)self.item.elapsedMS]
                                       font:[SPTheme mono:11]
                                      color:[SPTheme textDim]];
        [stack addArrangedSubview:meta];
    }
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (UILabel *)sectionTitle:(NSString *)text {
    return [self labelWithText:text.uppercaseString font:[SPTheme mono:11] color:[SPTheme textDim]];
}

- (void)copyCommand {
    UIPasteboard.generalPasteboard.string = self.item.command;
    [SPMotion hapticLight];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已复制"
        message:@"命令已复制到剪贴板，可粘贴到终端单独运行。"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end