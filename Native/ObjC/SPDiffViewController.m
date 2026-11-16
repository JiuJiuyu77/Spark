//
//  SPDiffViewController.m
//

#import "SPDiffViewController.h"
#import "SPTheme.h"
#import "SPCompat.h"

@interface SPDiffViewController ()
@property (nonatomic, copy) NSString *diffText;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation SPDiffViewController

- (instancetype)initWithDiff:(NSString *)diffText title:(NSString *)title {
    if ((self = [super init])) {
        _diffText = [diffText copy] ?: @"";
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.backgroundColor = [SPTheme codeBackground];
    self.textView.textContainerInset = UIEdgeInsetsMake(SPSpaceM, SPSpaceS, SPSpaceXL, SPSpaceS);
    self.textView.textContainer.lineFragmentPadding = 0;
    self.textView.attributedText = [self renderDiff];

    [self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 统计增删行数，放在副标题
    NSInteger add = 0, del = 0;
    for (NSString *line in [self.diffText componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"+"] && ![line hasPrefix:@"+++"]) add++;
        else if ([line hasPrefix:@"-"] && ![line hasPrefix:@"---"]) del++;
    }
    self.navigationItem.prompt = [NSString stringWithFormat:@"+%ld  −%ld", (long)add, (long)del];
}

- (NSAttributedString *)renderDiff {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];

    UIFont *mono = [SPTheme mono:11.5];
    BOOL dark = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);

    // 配色：绿色新增、红色删除、蓝色 hunk、灰色上下文
    UIColor *addBg = dark ? [UIColor colorWithRed:0.10 green:0.24 blue:0.14 alpha:1]
                          : [UIColor colorWithRed:0.88 green:0.97 blue:0.89 alpha:1];
    UIColor *delBg = dark ? [UIColor colorWithRed:0.28 green:0.11 blue:0.12 alpha:1]
                          : [UIColor colorWithRed:0.99 green:0.89 blue:0.89 alpha:1];
    UIColor *addFg = dark ? [UIColor colorWithRed:0.55 green:0.88 blue:0.60 alpha:1]
                          : [UIColor colorWithRed:0.10 green:0.45 blue:0.16 alpha:1];
    UIColor *delFg = dark ? [UIColor colorWithRed:0.95 green:0.55 blue:0.55 alpha:1]
                          : [UIColor colorWithRed:0.68 green:0.13 blue:0.13 alpha:1];
    UIColor *hunkFg = dark ? [UIColor colorWithRed:0.45 green:0.70 blue:0.98 alpha:1]
                           : [UIColor colorWithRed:0.10 green:0.35 blue:0.75 alpha:1];
    UIColor *metaFg = [SPTheme textDim];
    UIColor *ctxFg = [SPTheme text];

    NSArray<NSString *> *lines = [self.diffText componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *display = [line stringByAppendingString:(i + 1 < lines.count ? @"\n" : @"")];

        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        attrs[NSFontAttributeName] = mono;
        attrs[NSForegroundColorAttributeName] = ctxFg;

        if ([line hasPrefix:@"+++"] || [line hasPrefix:@"---"] ||
            [line hasPrefix:@"diff "] || [line hasPrefix:@"index "] ||
            [line hasPrefix:@"new file"] || [line hasPrefix:@"deleted file"]) {
            attrs[NSForegroundColorAttributeName] = metaFg;
        } else if ([line hasPrefix:@"@@"]) {
            attrs[NSForegroundColorAttributeName] = hunkFg;
            attrs[NSFontAttributeName] = [SPTheme mono:11.5];
        } else if ([line hasPrefix:@"+"]) {
            attrs[NSForegroundColorAttributeName] = addFg;
            attrs[NSBackgroundColorAttributeName] = addBg;
        } else if ([line hasPrefix:@"-"]) {
            attrs[NSForegroundColorAttributeName] = delFg;
            attrs[NSBackgroundColorAttributeName] = delBg;
        }

        [out appendAttributedString:[[NSAttributedString alloc] initWithString:display
                                                                  attributes:attrs]];
    }

    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 0;
    [out addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, out.length)];
    return out;
}

@end
