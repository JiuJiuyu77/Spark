//
//  SPReverseViewController.m
//

#import "SPReverseViewController.h"
#import "SPTheme.h"
#import "SPStore.h"
#import "SPSession.h"
#import "SPCompat.h"
#import "SPEditorViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchain.h"

typedef NS_ENUM(NSInteger, SPRMode) {
    SPRModeInfo = 0, SPRModeSymbols, SPRModeStrings, SPRModeImports, SPRModeSections, SPRModeEntropy,
};

@interface SPReverseViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy, nullable) NSString *binaryPath;
@property (nonatomic, strong) SPToolchainProfile *profile;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *binaryLabel;
@property (nonatomic, strong) UITextView *outputView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSArray *actions;
@property (nonatomic, strong) NSArray *actionSubs;
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
    self.title = @"逆向工具台";

    self.actions = @[@"Mach-O 架构信息", @"导出符号 / 入口点", @"导出的类与方法", @"导入的库与符号",
                     @"段与节", @"字符串（前 500 条）", @"熵值扫描（可疑加壳）",
                     @"注入 dylib", @"重签名", @"打开原始输出"];
    self.actionSubs = @[@"rabin2 -I", @"rabin2 -s", @"rabin2 -zz / ic", @"rabin2 -i",
                        @"rabin2 -S", @"rabin2 -z", @"rabin2 -e",
                        @"mt-inject-dylib", @"ldid -S", @"全文"];

    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [SPTheme surface];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    self.binaryLabel = [[UILabel alloc] init];
    self.binaryLabel.font = [SPTheme monoFont:11];
    self.binaryLabel.textColor = [SPTheme textDim];
    self.binaryLabel.numberOfLines = 2;
    self.binaryLabel.text = self.binaryPath ? [self.binaryPath stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]
                                            : @"未选择二进制";
    self.binaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.binaryLabel];

    UIButton *pick = [UIButton buttonWithType:UIButtonTypeSystem];
    [pick setTitle:@"选择" forState:UIControlStateNormal];
    [SPTheme styleSecondaryButton:pick];
    [pick addTarget:self action:@selector(pickBinary) forControlEvents:UIControlEventTouchUpInside];
    pick.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:pick];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [SPTheme accent];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.spinner];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"a"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    self.outputView = [[UITextView alloc] init];
    self.outputView.backgroundColor = [SPTheme codeBackground];
    self.outputView.textColor = [SPTheme text];
    self.outputView.font = [SPTheme monoFont:10.5];
    self.outputView.editable = NO;
    self.outputView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.outputView.translatesAutoresizingMaskIntoConstraints = NO;
    self.outputView.layer.cornerRadius = 10;
    self.outputView.clipsToBounds = YES;
    [self.view addSubview:self.outputView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:56],

        [self.binaryLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.binaryLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.binaryLabel.trailingAnchor constraintEqualToAnchor:pick.leadingAnchor constant:-8],

        [pick.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [pick.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [pick.widthAnchor constraintEqualToConstant:64],
        [pick.heightAnchor constraintEqualToConstant:32],

        [self.spinner.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.spinner.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-90],

        [self.table.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.55],

        [self.outputView.topAnchor constraintEqualToAnchor:self.table.bottomAnchor constant:4],
        [self.outputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.outputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.outputView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
    ]];

    self.outputView.text = @"选择上面任意一项开始分析。\n所有分析都调用 Rein 自带的 radare2 / mt-macho。";
}

- (void)pickBinary {
    SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:NSHomeDirectory()
                                                                              pickMode:YES fileFilters:nil
                                                                                onPick:^(NSString *path, BOOL isDir) {
        self.binaryPath = path;
        self.binaryLabel.text = [path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
    }];
    [self.navigationController pushViewController:b animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.actions.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"a"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"a"];
    cell.backgroundColor = [SPTheme surface];
    cell.textLabel.text = self.actions[ip.row];
    cell.textLabel.textColor = [SPTheme text];
    cell.textLabel.font = [SPTheme uiFont:14 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = self.actionSubs[ip.row];
    cell.detailTextLabel.font = [SPTheme monoFont:10];
    cell.detailTextLabel.textColor = [SPTheme textDim];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!self.binaryPath.length) { [self pickBinary]; return; }
    switch (ip.row) {
        case 0: [self runMode:SPRModeInfo]; break;
        case 1: [self runMode:SPRModeSymbols]; break;
        case 2: [self runMode:SPRModeStrings]; break;
        case 3: [self runMode:SPRModeImports]; break;
        case 4: [self runMode:SPRModeSections]; break;
        case 5: [self runMode:SPRModeStrings]; break;
        case 6: [self runMode:SPRModeEntropy]; break;
        case 7: [self injectDylib]; break;
        case 8: [self resign]; break;
        case 9: [self openFullOutput]; break;
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
    [script appendString:@"command -v \"$R2\" >/dev/null 2>&1 || [ -x \"$R2\" ] || { echo '找不到 rabin2，请先在工具链页安装逆向工具'; exit 1; }\n"];
    [script appendString:[NSString stringWithFormat:@"F=%@\n", q]];
    [script appendString:@"[ -f \"$F\" ] || { echo \"文件不存在: $F\"; exit 1; }\n"];
    [script appendString:@"echo \"文件: $F\"\n"];
    [script appendString:@"ls -lh \"$F\" | awk '{print \"大小: \" $5}'\n"];
    [script appendString:@"file \"$F\" 2>/dev/null || true\n"];
    [script appendString:@"echo '--------------------------------------------'\n"];

    if ([mode isEqualToString:@"info"]) {
        [script appendString:@"\"$R2\" -I \"$F\" 2>&1\n"];
        [script appendString:@"echo; echo '== 架构/平台 =='; \"$R2\" -H \"$F\" 2>&1 | head -5\n"];
        [script appendString:@"\"$MT\" info \"$F\" 2>&1 | head -40\n"];
    } else if ([mode isEqualToString:@"symbols"]) {
        [script appendString:@"\"$R2\" -s \"$F\" 2>&1 | head -2000\n"];
        [script appendString:@"echo; echo '== 入口 =='; \"$R2\" -e \"$F\" 2>&1\n"];
    } else if ([mode isEqualToString:@"strings"]) {
        [script appendString:@"\"$R2\" -zz -q \"$F\" 2>&1 | head -2000\n"];
        [script appendString:@"echo '== 类/方法（ObjC） =='; \"$R2\" -c 'ic' \"$F\" 2>&1 | head -400\n"];
    } else if ([mode isEqualToString:@"imports"]) {
        [script appendString:@"\"$R2\" -i \"$F\" 2>&1 | head -2000\n"];
    } else if ([mode isEqualToString:@"sections"]) {
        [script appendString:@"\"$R2\" -S \"$F\" 2>&1\n"];
    } else if ([mode isEqualToString:@"entropy"]) {
        [script appendString:@"\"$R2\" -e \"$F\" 2>&1\n"];
        [script appendString:@"echo; echo '== 段熵值（越高越可能被加壳/加密） =='; \n"];
        [script appendString:@"\"$R2\" -c 'iS~!' \"$F\" 2>&1 | head -60\n"];
    }
    [script appendString:@"echo; echo '--------------------------------------------'\n"];
    [script appendString:@"echo '提示：以上输出可复制保存，或在「打开原始输出」里查看完整版本'\n"];

    SPCommandResult *r = [SPSession runSyncShell:script
        environment:@{@"PATH": [[SPToolchain shared] pathPrefixForProfile:profile] ?: @""}
                                          cwd:NSHomeDirectory() timeout:120];
    NSString *out = r.stdoutText.length ? r.stdoutText : @"";
    if (r.stderrText.length) out = [out stringByAppendingFormat:@"\n[stderr]\n%@", r.stderrText];
    if (!out.length) out = [NSString stringWithFormat:@"(no output, exit=%ld)", (long)r.exitCode];
    return out;
}

- (void)runMode:(SPRMode)mode {
    [self.spinner startAnimating];
    self.outputView.text = @"分析中…";
    NSString *path = self.binaryPath;
    SPToolchainProfile *profile = self.profile ?: [[SPToolchain shared] localProfileWithSDK:nil error:NULL];
    NSArray *names = @[@"info", @"symbols", @"strings", @"imports", @"sections", @"strings", @"entropy"];
    NSString *m = names[mode];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [SPReverseViewController analyzeBinary:path profile:profile mode:m limit:2000];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.outputView.text = out;
            // 顺带落盘，方便「打开原始输出」
            NSString *p = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"rev-%@.txt", m]];
            [out writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        });
    });
}

- (void)openFullOutput {
    NSString *dir = [[SPStore shared] logsDirectory];
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL];
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
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"注入 dylib"
        message:@"输入要注入的 dylib 路径（会调用 mt-inject-dylib，先备份原文件）"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"/var/mobile/xxx.dylib";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
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
        [script appendString:@"echo '--- 注入后依赖 ---'\n"];
        [script appendString:@"\"$MT\" info \"$F\" 2>&1 | grep -i -E 'dylib|LC_LOAD' | head -20\n"];

        self.spinner.startAnimating;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            SPCommandResult *r = [SPSession runSyncShell:script
                environment:@{@"PATH": [[SPToolchain shared] pathPrefixForProfile:p] ?: @""}
                                                  cwd:NSHomeDirectory() timeout:120];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                self.outputView.text = [r.stdoutText stringByAppendingFormat:@"\n%@",
                                        r.stderrText.length ? r.stderrText : @""];
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)resign {
    SPToolchainProfile *p = self.profile;
    NSString *ldid = p.darwinBinDir.length ? [p.darwinBinDir stringByAppendingPathComponent:@"ldid"] : @"ldid";
    NSString *script = [NSString stringWithFormat:
        @"F=%@; LD=%@\n"
        @"[ -x \"$LD\" ] || command -v ldid >/dev/null 2>&1 || { echo '找不到 ldid'; exit 1; }\n"
        @"\"$LD\" -S \"$F\" 2>&1 && echo '签名完成' || echo '签名失败'\n"
        @"echo '--- codesign ---'; \"%@\" -I \"$F\" 2>&1 | head -5\n",
        [SPUtil shellQuote:self.binaryPath],
        [SPUtil shellQuote:ldid],
        p.reverseBinDir.length ? [p.reverseBinDir stringByAppendingPathComponent:@"rabin2"] : @"rabin2"];
    self.spinner.startAnimating;
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

@end
