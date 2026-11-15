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
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑"
            style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    }

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

@end
