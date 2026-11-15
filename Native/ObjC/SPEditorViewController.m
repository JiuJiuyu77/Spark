//
//  SPEditorViewController.m
//  代码查看/编辑 —— HIG：导航栏完成按钮 + 底部状态栏 + 等宽字体 + 跟随深浅色
//

#import "SPEditorViewController.h"
#import "SPTheme.h"
#import "SPSyntax.h"
#import "SPCompat.h"

@interface SPEditorViewController () <UITextViewDelegate, UIScrollViewDelegate>
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIView *gutter;
@property (nonatomic, strong) UILabel *gutterLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) BOOL editing;
@property (nonatomic, strong) UIView *findBar;
@property (nonatomic, strong) UITextField *findField;
@property (nonatomic, strong) UILabel *findCount;
@property (nonatomic, strong) NSArray<NSValue *> *findRanges;
@property (nonatomic, assign) NSInteger findIndex;
@end

@implementation SPEditorViewController

- (instancetype)initWithFilePath:(NSString *)path {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _filePath = [path copy];
        _readOnly = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme codeBackground];
    self.title = self.filePath.lastPathComponent;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    if (!self.readOnly) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑"
            style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    }
    UIBarButtonItem *find = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self action:@selector(toggleFind)];
    find.accessibilityLabel = @"查找";
    self.navigationItem.rightBarButtonItem = find;

    [self buildTextView];
    [self buildGutter];
    [self buildStatusBar];
    [self loadFile];
}

#pragma mark - 布局

- (void)buildGutter {
    self.gutter = [[UIView alloc] init];
    self.gutter.backgroundColor = [SPTheme background];
    self.gutter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.gutter];

    self.gutterLabel = [[UILabel alloc] init];
    self.gutterLabel.font = [SPTheme mono:12];
    self.gutterLabel.textColor = [SPTheme textDim];
    self.gutterLabel.numberOfLines = 0;
    self.gutterLabel.textAlignment = NSTextAlignmentRight;
    self.gutterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gutter addSubview:self.gutterLabel];
}

- (void)buildTextView {
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.backgroundColor = [SPTheme codeBackground];
    self.textView.textColor = [SPTheme codeText];
    self.textView.font = [SPTheme mono:12.5];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.delegate = self;
    self.textView.textContainerInset = UIEdgeInsetsMake(10, 10, 220, 10);
    self.textView.alwaysBounceVertical = YES;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];
}

- (void)buildStatusBar {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [SPTheme mono:10];
    self.statusLabel.textColor = [SPTheme textDim];
    self.statusLabel.backgroundColor = [SPTheme background];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    const CGFloat gutterWidth = 44;
    [NSLayoutConstraint activateConstraints:@[
        [self.gutter.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.gutter.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.gutter.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor],
        [self.gutter.widthAnchor constraintEqualToConstant:gutterWidth],

        [self.gutterLabel.topAnchor constraintEqualToAnchor:self.gutter.topAnchor constant:10],
        [self.gutterLabel.leadingAnchor constraintEqualToAnchor:self.gutter.leadingAnchor constant:4],
        [self.gutterLabel.trailingAnchor constraintEqualToAnchor:self.gutter.trailingAnchor constant:-8],

        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.gutter.trailingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.statusLabel.heightAnchor constraintEqualToConstant:24],
    ]];
}

#pragma mark - 读取

- (void)loadFile {
    NSString *code = [NSString stringWithContentsOfFile:self.filePath encoding:NSUTF8StringEncoding error:NULL];
    if (!code) code = @"（无法以 UTF-8 读取此文件，可能是二进制）";

    NSMutableAttributedString *hl = [[SPSyntax highlight:code
                                               language:[SPSyntax languageForFile:self.filePath]
                                                  color:[SPTheme codeText] darkTheme:YES] mutableCopy];
    if (hl.length) {
        [hl addAttribute:NSFontAttributeName value:[SPTheme mono:12.5] range:NSMakeRange(0, hl.length)];
    }
    self.textView.attributedText = hl;
    [self rebuildGutter];
    [self updateStatus];
}

#pragma mark - 行号

- (void)rebuildGutter {
    NSInteger count = [SPSyntax lineCount:self.textView.text];
    NSMutableString *s = [NSMutableString string];
    for (NSInteger i = 1; i <= count; i++) [s appendFormat:@"%ld\n", (long)i];
    self.gutterLabel.text = s;
    [self syncGutterOffset];
}

- (void)syncGutterOffset {
    CGFloat y = self.textView.contentOffset.y + self.textView.textContainerInset.top - 1;
    self.gutterLabel.frame = CGRectMake(self.gutterLabel.frame.origin.x, y,
                                        self.gutter.bounds.size.width - 12,
                                        MAX(self.gutter.bounds.size.height, 4000));
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self syncGutterOffset];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self syncGutterOffset];
}

#pragma mark - 编辑

- (void)toggleEditing {
    if (!self.editing) {
        self.editing = YES;
        self.textView.editable = YES;
        [self.textView becomeFirstResponder];
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                          target:self action:@selector(save)];
        self.statusLabel.text = @"编辑中…";
        return;
    }
    [self save];
}

- (void)save {
    NSString *text = self.textView.text;
    NSError *err = nil;
    if (![text writeToFile:self.filePath atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"保存失败"
            message:err.localizedDescription ?: @"未知错误" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        [SPMotion hapticError];
        return;
    }
    self.editing = NO;
    self.dirty = NO;
    self.textView.editable = NO;
    [self.textView resignFirstResponder];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];

    [self loadFile];
    [SPMotion hapticSuccess];
    if (self.onSave) self.onSave(self.filePath, text);
}

- (void)textViewDidChange:(UITextView *)textView {
    self.dirty = YES;
    [self rebuildGutter];
    [self updateStatus];
}

- (void)updateStatus {
    NSInteger lines = [SPSyntax lineCount:self.textView.text];
    unsigned long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:NULL].fileSize;
    NSString *format = [SPSyntax languageForFile:self.filePath].uppercaseString;
    self.statusLabel.text = [NSString stringWithFormat:@"%@   %ld 行   %@   UTF-8%@",
                             format, (long)lines, [SPUtil formatBytes:size],
                             self.dirty ? @"   ● 未保存" : @""];
    self.statusLabel.textColor = self.dirty ? [SPTheme warn] : [SPTheme textDim];
}

#pragma mark - 深色切换

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    self.view.backgroundColor = [SPTheme codeBackground];
    self.textView.backgroundColor = [SPTheme codeBackground];
    self.gutter.backgroundColor = [SPTheme background];
    [self loadFile];
}


#pragma mark - 查找 / 定位

- (void)toggleFind {
    if (self.findBar) {
        UIView *bar = self.findBar;
        self.findBar = nil;
        [SPMotion disappear:^{ bar.alpha = 0; } completion:^{ [bar removeFromSuperview]; }];
        self.findRanges = nil;
        return;
    }
    UIView *bar = [[UIView alloc] init];
    bar.backgroundColor = [SPTheme surface];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    self.findBar = bar;

    self.findField = [[UITextField alloc] init];
    self.findField.placeholder = @"查找";
    self.findField.font = [SPTheme mono:13];
    self.findField.textColor = [SPTheme text];
    self.findField.backgroundColor = [SPTheme background];
    self.findField.layer.cornerRadius = 8;
    self.findField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
    self.findField.leftViewMode = UITextFieldViewModeAlways;
    self.findField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.findField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.findField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.findField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.findField addTarget:self action:@selector(doFind) forControlEvents:UIControlEventEditingChanged];
    [bar addSubview:self.findField];

    self.findCount = [[UILabel alloc] init];
    self.findCount.font = [SPTheme mono:11];
    self.findCount.textColor = [SPTheme textDim];
    self.findCount.text = @"—";
    self.findCount.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.findCount];

    UIButton *prev = [UIButton buttonWithType:UIButtonTypeSystem];
    [prev setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    [prev addTarget:self action:@selector(findPrev) forControlEvents:UIControlEventTouchUpInside];
    prev.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:prev];

    UIButton *next = [UIButton buttonWithType:UIButtonTypeSystem];
    [next setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    [next addTarget:self action:@selector(findNext) forControlEvents:UIControlEventTouchUpInside];
    next.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:next];

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:44],

        [self.findField.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [self.findField.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.findField.heightAnchor constraintEqualToConstant:30],

        [self.findCount.leadingAnchor constraintEqualToAnchor:self.findField.trailingAnchor constant:8],
        [self.findCount.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.findCount.widthAnchor constraintEqualToConstant:52],

        [prev.leadingAnchor constraintEqualToAnchor:self.findCount.trailingAnchor constant:4],
        [prev.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [prev.widthAnchor constraintEqualToConstant:32],

        [next.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:2],
        [next.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [next.widthAnchor constraintEqualToConstant:32],
        [next.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-8],
    ]];

    // 正文下移：重新绑定 textView 顶部到查找栏底部
    for (NSLayoutConstraint *c in [self.view.constraints copy]) {
        if (c.firstItem == self.textView && c.firstAttribute == NSLayoutAttributeTop) [self.view removeConstraint:c];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
    ]];

    bar.alpha = 0;
    [SPMotion appear:^{ bar.alpha = 1; }];
    [self.findField becomeFirstResponder];
}

- (void)doFind {
    NSString *needle = self.findField.text ?: @"";
    NSString *haystack = self.textView.text ?: @"";
    if (!needle.length) { self.findRanges = nil; self.findCount.text = @"—"; return; }

    NSMutableArray *ranges = [NSMutableArray array];
    NSRange search = NSMakeRange(0, haystack.length);
    while (search.length > 0) {
        NSRange r = [haystack rangeOfString:needle options:NSCaseInsensitiveSearch range:search];
        if (r.location == NSNotFound) break;
        [ranges addObject:[NSValue valueWithRange:r]];
        NSUInteger nextStart = NSMaxRange(r);
        if (nextStart >= haystack.length) break;
        search = NSMakeRange(nextStart, haystack.length - nextStart);
    }
    self.findRanges = ranges;
    self.findIndex = ranges.count ? 0 : -1;
    [self highlightCurrentMatch];
}

- (void)highlightCurrentMatch {
    if (!self.findRanges.count || self.findIndex < 0) {
        self.findCount.text = @"无结果";
        return;
    }
    NSRange cur = [self.findRanges[self.findIndex] rangeValue];
    [self.textView scrollRangeToVisible:cur];

    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithAttributedString:self.textView.attributedText];
    if (a.length) {
        [a removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, a.length)];
        for (NSInteger i = 0; i < (NSInteger)self.findRanges.count; i++) {
            NSRange rr = [self.findRanges[i] rangeValue];
            if (NSMaxRange(rr) > a.length) continue;
            UIColor *c = (i == self.findIndex) ? [[SPTheme warn] colorWithAlphaComponent:0.55]
                                               : [[SPTheme warn] colorWithAlphaComponent:0.22];
            [a addAttribute:NSBackgroundColorAttributeName value:c range:rr];
        }
        self.textView.attributedText = a;
    }
    self.findCount.text = [NSString stringWithFormat:@"%ld/%lu", (long)(self.findIndex + 1),
                           (unsigned long)self.findRanges.count];
}

- (void)findNext {
    if (!self.findRanges.count) return;
    self.findIndex = (self.findIndex + 1) % (NSInteger)self.findRanges.count;
    [self highlightCurrentMatch];
}

- (void)findPrev {
    if (!self.findRanges.count) return;
    self.findIndex = (self.findIndex - 1 + (NSInteger)self.findRanges.count) % (NSInteger)self.findRanges.count;
    [self highlightCurrentMatch];
}

/// 构建失败时：跳到第一条 error: 所在行
- (void)jumpToFirstError { [self jumpToPattern:@"error:"]; }

- (void)jumpToPattern:(NSString *)pattern {
    NSString *text = self.textView.text ?: @"";
    NSRange r = [text rangeOfString:pattern options:NSCaseInsensitiveSearch];
    if (r.location == NSNotFound) { [SPMotion hapticError]; return; }
    NSRange lineRange = [text lineRangeForRange:r];
    [self.textView scrollRangeToVisible:lineRange];
    self.textView.selectedRange = lineRange;
    [SPMotion hapticSuccess];
}

@end
