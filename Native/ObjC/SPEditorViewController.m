//
//  SPEditorViewController.m
//

#import "SPEditorViewController.h"
#import "SPTheme.h"
#import "SPSyntax.h"

@interface SPEditorViewController () <UITextViewDelegate>
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIView *gutter;
@property (nonatomic, strong) UILabel *gutterLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) NSRange lastSeenVisible;
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

    NSString *language = [SPSyntax languageForFile:self.filePath];
    NSString *code = [NSString stringWithContentsOfFile:self.filePath encoding:NSUTF8StringEncoding error:NULL];
    if (!code) code = @"(无法以 UTF-8 读取此文件)";

    // 标题栏右侧：保存
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];

    // 行号槽
    self.gutter = [[UIView alloc] init];
    self.gutter.backgroundColor = [SPTheme surface];
    self.gutter.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.gutter];

    self.gutterLabel = [[UILabel alloc] init];
    self.gutterLabel.font = [SPTheme monoFont:12.5];
    self.gutterLabel.textColor = [SPTheme textDim];
    self.gutterLabel.numberOfLines = 0;
    self.gutterLabel.textAlignment = NSTextAlignmentRight;
    self.gutterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gutter addSubview:self.gutterLabel];

    // 正文
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:
        [SPSyntax highlight:code language:language color:[SPTheme text] darkTheme:YES]];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    [storage addLayoutManager:lm];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    container.widthTracksTextView = YES;
    [lm addTextContainer:container];

    self.textView = [[UITextView alloc] initWithFrame:CGRectZero textContainer:container];
    self.textView.backgroundColor = [SPTheme codeBackground];
    self.textView.font = [SPTheme monoFont:12.5];
    self.textView.textColor = [SPTheme text];
    self.textView.editable = NO;
    self.textView.delegate = self;
    self.textView.textContainerInset = UIEdgeInsetsMake(10, 10, 200, 10);
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.keyboardAppearance = UIKeyboardAppearanceDark;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    [self.view addSubview:self.textView];

    // 底部状态条
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [SPTheme monoFont:11];
    self.statusLabel.textColor = [SPTheme textDim];
    self.statusLabel.backgroundColor = [SPTheme surface];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    CGFloat gutterWidth = 44;
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
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.statusLabel.heightAnchor constraintEqualToConstant:24],
    ]];

    [self rebuildGutter];
    [self updateStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = [SPTheme accent];
}

#pragma mark - 行号

- (void)rebuildGutter {
    NSInteger count = [SPSyntax lineCount:self.textView.text];
    NSMutableString *s = [NSMutableString string];
    for (NSInteger i = 1; i <= count; i++) [s appendFormat:@"%ld\n", (long)i];
    self.gutterLabel.text = s;
    // 行号随文本滚动对齐：gutter 与 textView 同步偏移
    [self syncGutterOffset];
}

- (void)syncGutterOffset {
    CGRect frame = CGRectMake(0, self.textView.contentOffset.y + self.textView.textContainerInset.top - 1,
                              self.gutter.bounds.size.width, self.gutter.bounds.size.height);
    self.gutterLabel.frame = CGRectMake(self.gutterLabel.frame.origin.x, frame.origin.y,
                                        self.gutter.bounds.size.width - 12,
                                        MAX(self.gutter.bounds.size.height, 2000));
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
    if (self.readOnly) {
        self.textView.editable = YES;
        self.textView.backgroundColor = [SPTheme codeBackground];
        [self.textView becomeFirstResponder];
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
        self.statusLabel.text = @"编辑中…";
        return;
    }
    [self save];
}

- (void)save {
    NSString *text = self.textView.text;
    NSError *err = nil;
    BOOL ok = [text writeToFile:self.filePath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"保存失败"
            message:err.localizedDescription ?: @"未知错误" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    self.textView.editable = NO;
    [self.textView resignFirstResponder];
    self.dirty = NO;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];

    // 重新着色
    NSMutableAttributedString *hl = [[SPSyntax highlight:text
                                                language:[SPSyntax languageForFile:self.filePath]
                                                   color:[SPTheme text] darkTheme:YES] mutableCopy];
    [hl addAttribute:NSFontAttributeName value:[SPTheme monoFont:12.5] range:NSMakeRange(0, hl.length)];
    self.textView.attributedText = hl;

    [self rebuildGutter];
    [self updateStatus];
    if (self.onSave) self.onSave(self.filePath, text);
}

- (void)textViewDidChange:(UITextViewDelegate *)tv {
    self.dirty = YES;
    [self rebuildGutter];
    [self updateStatus];
}

- (void)updateStatus {
    NSInteger lines = [SPSyntax lineCount:self.textView.text];
    unsigned long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:NULL].fileSize;
    NSString *format = [SPSyntax languageForFile:self.filePath].uppercaseString;
    self.statusLabel.text = [NSString stringWithFormat:@"%@  %ld 行  %@  UTF-8  %@",
                             format, (long)lines, [SPUtil formatBytes:size], self.dirty ? @"●未保存" : @""];
}

@end
