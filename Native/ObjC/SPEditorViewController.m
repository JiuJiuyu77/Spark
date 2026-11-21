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
/// 替换输入框（与查找栏同处，第二行）
@property (nonatomic, strong, nullable) UITextField *replaceField;
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
        [self.gutterLabel.trailingAnchor constraintEqualToAnchor:self.gutter.trailingAnchor constant:-SPSpaceXS],

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

    // 重新着色（节流：连续输入时合并成一次）。
    // 之前这里只更新 gutter 与状态栏 —— 编辑之后语法高亮就没了，
    // 输入的文字全变成默认黑色，看起来像高亮失效。
    [self scheduleHighlight];
}

/// 节流后的语法高亮。大文件或快速连打时避免每次按键都跑正则。
- (void)scheduleHighlight {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(applyHighlightNow)
                                               object:nil];
    [self performSelector:@selector(applyHighlightNow) withObject:nil afterDelay:0.25];
}

- (void)applyHighlightNow {
    NSString *code = self.textView.text ?: @"";
    if (!code.length) return;

    // 超大文件跳过（正则在高亮 6 类语法时会明显卡顿）
    if (code.length > 400000) return;

    NSRange sel = self.textView.selectedRange;
    CGPoint offset = self.textView.contentOffset;

    BOOL dark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    NSMutableAttributedString *hl = [[SPSyntax highlight:code
                                               language:[SPSyntax languageForFile:self.filePath]
                                                  color:[SPTheme codeText]
                                              darkTheme:dark] mutableCopy];
    if (hl.length) {
        // 字号与 loadFile 保持一致，否则重着色后字会变大
        [hl addAttribute:NSFontAttributeName value:[SPTheme mono:12.5] range:NSMakeRange(0, hl.length)];
        self.textView.attributedText = hl;
        // 恢复选区与滚动位置，否则会跳回顶部
        if (NSMaxRange(sel) <= self.textView.text.length) self.textView.selectedRange = sel;
        self.textView.contentOffset = offset;
    }
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
    self.findField.layer.cornerRadius = SPRadiusS;
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

    // ── 第二行：替换 ──
    self.replaceField = [[UITextField alloc] init];
    self.replaceField.placeholder = @"替换为";
    self.replaceField.font = [SPTheme mono:13];
    self.replaceField.textColor = [SPTheme text];
    self.replaceField.backgroundColor = [SPTheme background];
    self.replaceField.layer.cornerRadius = SPRadiusS;
    self.replaceField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
    self.replaceField.leftViewMode = UITextFieldViewModeAlways;
    self.replaceField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.replaceField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.replaceField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.replaceField.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.replaceField];

    UIButton *replaceOne = [UIButton buttonWithType:UIButtonTypeSystem];
    [replaceOne setTitle:@"替换" forState:UIControlStateNormal];
    replaceOne.titleLabel.font = [UIFont systemFontOfSize:13];
    [replaceOne addTarget:self action:@selector(replaceCurrent) forControlEvents:UIControlEventTouchUpInside];
    replaceOne.translatesAutoresizingMaskIntoConstraints = NO;
    replaceOne.accessibilityLabel = @"替换当前匹配";
    [bar addSubview:replaceOne];

    UIButton *replaceAll = [UIButton buttonWithType:UIButtonTypeSystem];
    [replaceAll setTitle:@"全部" forState:UIControlStateNormal];
    replaceAll.titleLabel.font = [UIFont systemFontOfSize:13];
    [replaceAll addTarget:self action:@selector(replaceAll) forControlEvents:UIControlEventTouchUpInside];
    replaceAll.translatesAutoresizingMaskIntoConstraints = NO;
    replaceAll.accessibilityLabel = @"替换全部匹配";
    [bar addSubview:replaceAll];

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:88],

        [self.findField.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:SPSpaceS],
        [self.findField.topAnchor constraintEqualToAnchor:bar.topAnchor constant:7],
        [self.findField.heightAnchor constraintEqualToConstant:30],

        [self.findCount.leadingAnchor constraintEqualToAnchor:self.findField.trailingAnchor constant:SPSpaceXS],
        [self.findCount.topAnchor constraintEqualToAnchor:bar.topAnchor constant:15],
        [self.findCount.widthAnchor constraintEqualToConstant:52],

        [prev.leadingAnchor constraintEqualToAnchor:self.findCount.trailingAnchor constant:4],
        [prev.topAnchor constraintEqualToAnchor:bar.topAnchor constant:7],
        [prev.widthAnchor constraintEqualToConstant:32],

        [next.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:2],
        [next.topAnchor constraintEqualToAnchor:bar.topAnchor constant:7],
        [next.widthAnchor constraintEqualToConstant:32],
        [next.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-SPSpaceXS],

        // 第二行：替换
        [self.replaceField.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:SPSpaceS],
        [self.replaceField.topAnchor constraintEqualToAnchor:self.findField.bottomAnchor constant:6],
        [self.replaceField.heightAnchor constraintEqualToConstant:30],
        [self.replaceField.trailingAnchor constraintEqualToAnchor:replaceOne.leadingAnchor constant:-SPSpaceXS],

        [replaceOne.topAnchor constraintEqualToAnchor:self.replaceField.topAnchor],
        [replaceOne.widthAnchor constraintEqualToConstant:44],
        [replaceOne.heightAnchor constraintEqualToConstant:30],

        [replaceAll.leadingAnchor constraintEqualToAnchor:replaceOne.trailingAnchor constant:2],
        [replaceAll.topAnchor constraintEqualToAnchor:self.replaceField.topAnchor],
        [replaceAll.widthAnchor constraintEqualToConstant:44],
        [replaceAll.heightAnchor constraintEqualToConstant:30],
        [replaceAll.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-SPSpaceXS],
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

#pragma mark - 替换

/// 替换当前选中的匹配项。没有选中时先跳到下一个匹配再替换。
- (void)replaceCurrent {
    NSString *needle = self.findField.text ?: @"";
    if (!needle.length) return;

    NSString *replacement = self.replaceField.text ?: @"";
    NSRange sel = self.textView.selectedRange;
    NSString *text = self.textView.text ?: @"";

    BOOL onMatch = NO;
    if (sel.location != NSNotFound && sel.length == needle.length &&
        NSMaxRange(sel) <= text.length) {
        NSString *cur = [text substringWithRange:sel];
        onMatch = [cur isEqualToString:needle];
    }
    if (!onMatch) {
        // 先定位到下一个匹配
        [self findNext];
        return;
    }

    // 用 textStorage 替换，保留撤销栈（比直接改 text 更符合编辑器预期）
    NSRange target = sel;
    self.textView.textStorage.mutableString.string = [text stringByReplacingCharactersInRange:target
                                                                                 withString:replacement];
    NSRange after = NSMakeRange(target.location + replacement.length, 0);
    self.textView.selectedRange = after;
    [self textViewDidChange:self.textView];

    // 重新统计并跳到下一个
    [self doFind];
    [self findNext];
    [SPMotion hapticLight];
}

/// 替换全部
- (void)replaceAll {
    NSString *needle = self.findField.text ?: @"";
    if (!needle.length) return;

    NSString *replacement = self.replaceField.text ?: @"";
    NSString *text = self.textView.text ?: @"";

    // 先算出会有多少处，替换后告知用户
    NSUInteger count = 0;
    NSRange search = NSMakeRange(0, text.length);
    while (search.length) {
        NSRange found = [text rangeOfString:needle options:0 range:search];
        if (found.location == NSNotFound) break;
        count++;
        NSUInteger nextStart = NSMaxRange(found);
        if (nextStart >= text.length) break;
        search = NSMakeRange(nextStart, text.length - nextStart);
        if (count > 100000) break;  // 防御：避免极端情况长时间占用
    }
    if (!count) return;

    NSString *replaced = [text stringByReplacingOccurrencesOfString:needle withString:replacement];
    self.textView.textStorage.mutableString.string = replaced;
    [self textViewDidChange:self.textView];
    [self doFind];
    [SPMotion hapticSuccess];

    SPLog(@"[编辑器] 替换全部：%@ → %@（%lu 处）", needle, replacement, (unsigned long)count);
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"已替换全部"
        message:[NSString stringWithFormat:@"共 %lu 处（记得保存）", (unsigned long)count]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
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
