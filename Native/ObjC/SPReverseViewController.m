//
//  SPReverseViewController.m
//  逆向工具台 —— HIG：分段控件切换「分析 / 输出」+ 顶部已选二进制卡片
//

#import "SPReverseViewController.h"
#import "SPTheme.h"
#import "SPStore.h"
#import "SPSession.h"
#import "SPCompat.h"
#import "SPEditorViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchain.h"
#import "SPHeaderExport.h"

typedef NS_ENUM(NSInteger, SPRevAction) {
    SPRevActionInfo = 0,
    SPRevActionSymbols,
    SPRevActionStrings,
    SPRevActionImports,
    SPRevActionSections,
    SPRevActionEntropy,
    SPRevActionInject,
    SPRevActionResign,
    SPRevActionExportHeaders,
    SPRevActionCount,
};

@interface SPReverseViewController ()
@property (nonatomic, copy, nullable) NSString *binaryPath;
@property (nonatomic, strong) SPToolchainProfile *profile;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *binaryLabel;
@property (nonatomic, strong) UITextView *outputView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSArray<NSString *> *subtitles;
@property (nonatomic, strong) NSArray<NSString *> *symbols;
@property (nonatomic, strong) SPCardView *headerCard;
@end

@implementation SPReverseViewController

- (instancetype)initWithBinaryPath:(NSString *)binaryPath profile:(SPToolchainProfile *)profile {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _binaryPath = [binaryPath copy];
        _profile = profile;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"逆向";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.titles = @[@"架构与头信息", @"导出符号与入口", @"字符串与 ObjC 类",
                    @"导入的库与符号", @"段与节", @"熵值（加壳检测）",
                    @"注入动态库", @"重新签名", @"导出 ObjC 头文件", @"打开原始输出"];
    self.subtitles = @[@"rabin2 -I", @"rabin2 -s", @"rabin2 -zz / ic", @"rabin2 -i",
                       @"rabin2 -S", @"rabin2 -e", @"mt-inject-dylib", @"ldid -S",
                       @"类名 + 方法名 → .h", @"完整文本"];
    self.symbols = @[@"info.circle", @"list.bullet.indent", @"text.magnifyingglass", @"link",
                     @"square.stack.3d.up", @"chart.bar.xaxis", @"syringe", @"signature",
                     @"doc.badge.plus", @"doc.text"];

    [self buildHeader];
    [self buildTable];
    [self buildOutput];
    [self buildSegment];
}

- (void)buildHeader {
    SPCardView *card = [[SPCardView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];
    self.headerCard = card;

    self.binaryLabel = [[UILabel alloc] init];
    self.binaryLabel.font = [SPTheme mono:11];
    self.binaryLabel.textColor = [SPTheme textDim];
    self.binaryLabel.numberOfLines = 2;
    self.binaryLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.binaryLabel.text = self.binaryPath
        ? [self.binaryPath stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]
        : @"尚未选择二进制，点右侧「选择」开始";
    self.binaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:self.binaryLabel];

    UIButton *pick = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration tintedButtonConfiguration];
    cfg.title = @"选择";
    cfg.image = [UIImage systemImageNamed:@"doc.badge.plus"];
    cfg.imagePadding = 6;
    cfg.baseBackgroundColor = [[SPTheme accent] colorWithAlphaComponent:0.12];
    cfg.baseForegroundColor = [SPTheme accent];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    pick.configuration = cfg;
    [pick addTarget:self action:@selector(pickBinary) forControlEvents:UIControlEventTouchUpInside];
    pick.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:pick];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [SPTheme accent];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.binaryLabel.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [self.binaryLabel.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [self.binaryLabel.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor],
        [self.binaryLabel.trailingAnchor constraintEqualToAnchor:pick.leadingAnchor constant:-10],

        [self.spinner.centerYAnchor constraintEqualToAnchor:pick.centerYAnchor],
        [self.spinner.trailingAnchor constraintEqualToAnchor:pick.leadingAnchor constant:-8],

        [pick.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [pick.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [pick.heightAnchor constraintGreaterThanOrEqualToConstant:32],
    ]];
}

- (void)buildSegment {
    self.segment = [[UISegmentedControl alloc] initWithItems:@[@"操作", @"输出"]];
    self.segment.selectedSegmentIndex = 0;
    self.segment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segment;
}

- (void)buildTable {
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"a"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
}

- (void)buildOutput {
    self.outputView = [[UITextView alloc] init];
    self.outputView.backgroundColor = [SPTheme codeBackground];
    self.outputView.textColor = [SPTheme codeText];
    self.outputView.font = [SPTheme mono:11];
    self.outputView.editable = NO;
    self.outputView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.outputView.translatesAutoresizingMaskIntoConstraints = NO;
    [SPTheme round:self.outputView radius:12];
    self.outputView.clipsToBounds = YES;
    self.outputView.text = @"选择上面的任意一项开始分析。\n\n所有分析都调用 Rein 自带的 radare2 / mt-macho。";
    [self.view addSubview:self.outputView];
    self.outputView.hidden = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 两个视图叠在同一区域，用 hidden 切换，避免反复重建约束
    UIEdgeInsets pad = UIEdgeInsetsMake(0, 0, 0, 0);
    (void)pad;
}

- (void)segmentChanged {
    BOOL showOutput = self.segment.selectedSegmentIndex == 1;
    [SPMotion animate:^{
        self.table.alpha = showOutput ? 0 : 1;
        self.outputView.alpha = showOutput ? 1 : 0;
    } duration:0.18];
    self.table.hidden = NO;
    self.outputView.hidden = NO;
    self.table.userInteractionEnabled = !showOutput;
}

#pragma mark - 选择二进制

- (void)pickBinary {
    SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:NSHomeDirectory()
                                                                              pickMode:YES fileFilters:nil
                                                                                onPick:^(NSString *path, BOOL isDir) {
        self.binaryPath = path;
        self.binaryLabel.text = [path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
        self.binaryLabel.textColor = [SPTheme text];
        [SPMotion hapticSuccess];
    }];
    [self.navigationController pushViewController:b animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return SPRevActionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return @"分析工具"; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"a"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"a"];
    [SPTheme styleCell:cell];
    cell.textLabel.text = self.titles[ip.row];
    cell.detailTextLabel.text = self.subtitles[ip.row];
    cell.imageView.image = [UIImage systemImageNamed:self.symbols[ip.row]];
    cell.imageView.tintColor = (ip.row >= SPRevActionInject) ? [SPTheme warn] : [SPTheme accent];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!self.binaryPath.length) { [self pickBinary]; return; }
    [SPMotion hapticLight];

    switch (ip.row) {
        case SPRevActionInfo: [self runMode:@"info"]; break;
        case SPRevActionSymbols: [self runMode:@"symbols"]; break;
        case SPRevActionStrings: [self runMode:@"strings"]; break;
        case SPRevActionImports: [self runMode:@"imports"]; break;
        case SPRevActionSections: [self runMode:@"sections"]; break;
        case SPRevActionEntropy: [self runMode:@"entropy"]; break;
        case SPRevActionInject: [self injectDylib]; break;
        case SPRevActionResign: [self resign]; break;
        case SPRevActionExportHeaders: [self exportHeaders]; break;
        default: [self openFullOutput]; break;
    }
}

#pragma mark - 分析

+ (NSString *)analyzeBinary:(NSString *)path profile:(SPToolchainProfile *)profile
                       mode:(NSString *)mode limit:(NSInteger)limit {
    NSString *r2 = profile.reverseBinDir.length ? [profile.reverseBinDir stringByAppendingPathComponent:@"rabin2"] : @"rabin2";
    NSString *mtMacho = profile.reverseBinDir.length ? [profile.reverseBinDir stringByAppendingPathComponent:@"mt-macho"] : @"mt-macho";
    NSString *q = [SPUtil shellQuote:path];

    NSMutableString *script = [NSMutableString string];
    [script appendString:@"export LC_ALL=en_US.UTF-8\n"];
    [script appendString:[NSString stringWithFormat:@"R2=%@; MT=%@\n", [SPUtil shellQuote:r2], [SPUtil shellQuote:mtMacho]]];
    [script appendString:@"{ command -v \"$R2\" >/dev/null 2>&1 || [ -x \"$R2\" ]; } || { echo '找不到 rabin2：请先在工具链页确认逆向工具已安装'; exit 1; }\n"];
    [script appendString:[NSString stringWithFormat:@"F=%@\n", q]];
    [script appendString:@"[ -f \"$F\" ] || { echo \"文件不存在: $F\"; exit 1; }\n"];
    [script appendString:@"echo \"文件  $F\"\n"];
    [script appendString:@"ls -lh \"$F\" | awk '{print \"大小  \" $5}'\n"];
    [script appendString:@"file \"$F\" 2>/dev/null || true\n"];
    [script appendString:@"echo '--------------------------------------------'\n"];

    if ([mode isEqualToString:@"info"]) {
        [script appendString:@"\"$R2\" -I \"$F\" 2>&1\n"];
        [script appendString:@"echo; echo '== 架构 =='; \"$R2\" -H \"$F\" 2>&1 | head -6\n"];
        [script appendString:@"\"$MT\" info \"$F\" 2>&1 | head -40\n"];
    } else if ([mode isEqualToString:@"symbols"]) {
        [script appendString:@"\"$R2\" -s \"$F\" 2>&1 | head -2000\n"];
        [script appendString:@"echo; echo '== 入口 =='; \"$R2\" -e \"$F\" 2>&1\n"];
    } else if ([mode isEqualToString:@"strings"]) {
        [script appendString:@"\"$R2\" -zz -q \"$F\" 2>&1 | head -1500\n"];
        [script appendString:@"echo '== ObjC 类与方法 =='; \"$R2\" -c 'ic' \"$F\" 2>&1 | head -400\n"];
    } else if ([mode isEqualToString:@"imports"]) {
        [script appendString:@"\"$R2\" -i \"$F\" 2>&1 | head -2000\n"];
    } else if ([mode isEqualToString:@"sections"]) {
        [script appendString:@"\"$R2\" -S \"$F\" 2>&1\n"];
    } else if ([mode isEqualToString:@"entropy"]) {
        [script appendString:@"\"$R2\" -e \"$F\" 2>&1\n"];
        [script appendString:@"echo; echo '== 段熵值（越高越可能被加壳/加密） =='\n"];
        [script appendString:@"\"$R2\" -c 'iS~!' \"$F\" 2>&1 | head -60\n"];
    }
    [script appendString:@"echo; echo '--------------------------------------------'\n"];
    [script appendString:@"echo '提示：点右上角「输出」标签可看完整文本，也能一键复制'\n"];

    SPCommandResult *r = [SPSession runSyncShell:script
        environment:@{@"PATH": [[SPToolchain shared] pathPrefixForProfile:profile] ?: @""}
                                          cwd:NSHomeDirectory() timeout:120];
    NSString *out = r.stdoutText.length ? r.stdoutText : @"";
    if (r.stderrText.length) out = [out stringByAppendingFormat:@"\n[stderr]\n%@", r.stderrText];
    if (!out.length) out = [NSString stringWithFormat:@"（没有输出，退出码 %ld）", (long)r.exitCode];
    return out;
}

- (void)runMode:(NSString *)mode {
    [self.spinner startAnimating];
    self.outputView.text = @"分析中…";
    self.segment.selectedSegmentIndex = 1;
    [self segmentChanged];

    NSString *path = self.binaryPath;
    SPToolchainProfile *profile = self.profile ?: [[SPToolchain shared] localProfileWithSDK:nil error:NULL];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [SPReverseViewController analyzeBinary:path profile:profile mode:mode limit:2000];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.spinner stopAnimating];
            self.outputView.text = out;
            NSString *p = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"rev-%@.txt", mode]];
            [out writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        });
    });
}

- (void)openFullOutput {
    NSString *dir = [[SPStore shared] logsDirectory];
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL] ?: @[];
    NSMutableArray *revs = [NSMutableArray array];
    for (NSString *f in files) if ([f hasPrefix:@"rev-"]) [revs addObject:f];
    if (!revs.count) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"还没有分析结果"
            message:@"先点上面任意一项跑一次分析" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    NSString *latest = [[revs sortedArrayUsingSelector:@selector(compare:)] lastObject];
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:[dir stringByAppendingPathComponent:latest]];
    [self.navigationController pushViewController:e animated:YES];
}

#pragma mark - 注入 / 签名

- (void)injectDylib {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"注入动态库"
        message:@"输入要注入的 dylib 路径。会先备份原文件，再调用 mt-inject-dylib。"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"/var/mobile/xxx.dylib";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"注入" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        NSString *dylib = a.textFields[0].text;
        if (!dylib.length) return;
        SPToolchainProfile *p = self.profile;
        NSString *mt = p.reverseBinDir.length ? [p.reverseBinDir stringByAppendingPathComponent:@"mt-inject-dylib"] : @"mt-inject-dylib";
        NSMutableString *script = [NSMutableString string];
        [script appendString:[NSString stringWithFormat:@"F=%@; D=%@; MT=%@\n",
                              [SPUtil shellQuote:self.binaryPath], [SPUtil shellQuote:dylib], [SPUtil shellQuote:mt]]];
        [script appendString:@"[ -f \"$D\" ] || { echo \"dylib 不存在: $D\"; exit 1; }\n"];
        [script appendString:@"cp \"$F\" \"$F.bak-$(date +%s)\" && echo \"已备份到 $F.bak-*\"\n"];
        [script appendString:@"\"$MT\" \"$F\" \"$D\" 2>&1 | head -40\n"];
        [script appendString:@"echo '--- 注入后的依赖 ---'\n"];
        [script appendString:@"\"$MT\" info \"$F\" 2>&1 | grep -i -E 'dylib|LC_LOAD' | head -20\n"];

        [self.spinner startAnimating];
        self.segment.selectedSegmentIndex = 1;
        [self segmentChanged];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            SPCommandResult *r = [SPSession runSyncShell:script
                environment:@{@"PATH": [[SPToolchain shared] pathPrefixForProfile:p] ?: @""}
                                                  cwd:NSHomeDirectory() timeout:120];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                self.outputView.text = [r.stdoutText stringByAppendingFormat:@"\n%@", r.stderrText ?: @""];
                [SPMotion hapticSuccess];
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)resign {
    SPToolchainProfile *p = self.profile;
    NSString *ldid = p.darwinBinDir.length ? [p.darwinBinDir stringByAppendingPathComponent:@"ldid"] : @"ldid";
    NSString *rabin2 = p.reverseBinDir.length ? [p.reverseBinDir stringByAppendingPathComponent:@"rabin2"] : @"rabin2";
    NSString *script = [NSString stringWithFormat:
        @"F=%@; LD=%@\n"
         "[ -x \"$LD\" ] || command -v ldid >/dev/null 2>&1 || { echo '找不到 ldid'; exit 1; }\n"
         "\"$LD\" -S \"$F\" 2>&1 && echo '签名完成' || echo '签名失败'\n"
         "echo '--- 校验 ---'; \"%@\" -I \"$F\" 2>&1 | head -5\n",
        [SPUtil shellQuote:self.binaryPath], [SPUtil shellQuote:ldid], [SPUtil shellQuote:rabin2]];
    [self.spinner startAnimating];
    self.segment.selectedSegmentIndex = 1;
    [self segmentChanged];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SPCommandResult *r = [SPSession runSyncShell:script
            environment:@{@"PATH": [[SPToolchain shared] pathPrefixForProfile:p] ?: @""}
                                              cwd:NSHomeDirectory() timeout:60];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.outputView.text = [r.stdoutText stringByAppendingFormat:@"\n%@", r.stderrText ?: @""];
        });
    });
}

/// 让分段控件在布局后生效（table 与 output 叠放）
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self.table removeFromSuperview];
        [self.view addSubview:self.table];
        [self.view addSubview:self.outputView];
        [NSLayoutConstraint activateConstraints:@[
            [self.table.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:8],
            [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.table.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

            [self.outputView.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:8],
            [self.outputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
            [self.outputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
            [self.outputView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        ]];
        self.outputView.alpha = 0;
        self.outputView.hidden = NO;
    });
}


#pragma mark - 导出头文件

- (void)exportHeaders {
    NSString *dir = [[[SPStore shared] archivesDirectory]
                     stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"headers-%@", [SPUtil timestampSlug]]];
    [self.spinner startAnimating];
    self.outputView.text = @"正在提取 ObjC 元数据…";
    self.segment.selectedSegmentIndex = 1;
    [self segmentChanged];

    NSString *bin = self.binaryPath;
    __weak typeof(self) weakSelf = self;
    [SPHeaderExport exportHeadersFromApp:bin outputDir:dir
        progress:^(NSString *status) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            self.outputView.text = status;
        }
        completion:^(BOOL ok, NSInteger count, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.spinner stopAnimating];
            if (!ok) {
                self.outputView.text = [NSString stringWithFormat:@"导出失败：%@", error.localizedDescription];
                [SPMotion hapticError];
                return;
            }
            [SPMotion hapticSuccess];
            self.outputView.text = [NSString stringWithFormat:
                @"已导出 %ld 个头文件到：\n%@\n\n点下面的按钮打开目录。", (long)count, dir];
            SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
                initWithRootPath:dir pickMode:NO fileFilters:@[@"h"] onPick:nil];
            [self.navigationController pushViewController:b animated:YES];
        }];
}

@end
