//
//  SPToolchainViewController.m
//  工具链页 —— HIG：InsetGrouped 分组、SF Symbols 状态、底部一键自检
//

#import "SPToolchainViewController.h"
#import "SPSelfTestViewController.h"
#import "SPHealthViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPToolchain.h"
#import "SPStore.h"
#import "SPSession.h"
#import "SPCompat.h"
#import "SPEditorViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchainDownloader.h"

/// 分组定义，避免一堆 magic number
typedef NS_ENUM(NSInteger, SPToolSection) {
    SPToolSectionStatus = 0,
    SPToolSectionSDK,
    SPToolSectionTarget,
    SPToolSectionDisplay,
    SPToolSectionAbout,
    SPToolSectionCount,
};

@interface SPToolchainViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSString *> *componentKeys;
@end

@implementation SPToolchainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"工具链";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    // 与 SPToolchainComponent 枚举一一对应
    // 必须与 SPToolchainComponent 枚举逐项对应（含 Swift）。
    // 之前这里只有 8 项而枚举有 9 个，numberOfRows 返回 9，
    // 滚动到第 8 行时 componentKeys[8] 越界 → NSRangeException 崩溃。
    self.componentKeys = @[@"Theos", @"iPhoneOS SDK", @"Darwin 编译工具", @"OLLVM 混淆",
                           @"逆向工具", @"Python", @"Node", @"SSH（远程编译）", @"Swift"];

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"wrench.and.screwdriver.fill", @"工具链", @"探测、展开与诊断", [SPTheme accent], 320);

    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(refreshAction)];
    refresh.accessibilityLabel = @"重新扫描";
    self.navigationItem.rightBarButtonItem = refresh;

    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    [[SPToolchain shared] rescan];
    [self.table reloadData];
}

- (void)refreshAction {
    [SPMotion hapticLight];

    // 刷新时顺便自动找一次 Rein / DSH.app：
    // 用户装了 Rein 但没手动填路径的情况很常见。
    SPToolchain *tc = [SPToolchain shared];
    NSString *before = tc.reinRoot;
    NSString *found = [SPToolchain discoverReinRoot];
    if (found.length && ![found isEqualToString:before]) {
        tc.reinRoot = found;
        [[NSUserDefaults standardUserDefaults] setObject:found forKey:@"Workbench.reinRoot"];
        [self toast:[NSString stringWithFormat:@"已发现 Rein：%@", found.lastPathComponent]];
    }

    [tc rescan];
    [self refresh];

    if (!found.length) [self toast:@"已重新扫描（未找到 Rein 目录）"];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SPToolSectionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SPToolSectionStatus: return @"探测结果";
        case SPToolSectionSDK: return @"默认 SDK";
        case SPToolSectionTarget: return @"构建目标";
        case SPToolSectionDisplay: return @"显示与反馈";
        default: return @"维护";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SPToolSectionStatus) {
        NSArray *remedies = [[SPToolchain shared].scan remedies];
        return remedies.count ? [remedies componentsJoinedByString:@"\n"] : @"全部组件都已就绪，可以开始编译。";
    }
    if (s == SPToolSectionDisplay) return @"编译期间会自动保持屏幕常亮，结束后恢复。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SPToolSectionStatus: return (NSInteger)self.componentKeys.count;
        // SDK 三态：16.5 内置、17.0 / 26.5 按需下载。
        // 固定 3 行，不随 availableSDKs 数量变化（否则「未安装」的无法展示下载入口）。
        case SPToolSectionSDK: return 3;
        case SPToolSectionTarget: return 4;
        case SPToolSectionDisplay: return 3;
        case SPToolSectionAbout: return 2;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.detailTextLabel.textColor = [SPTheme textDim];

    SPToolchainScan *scan = [SPToolchain shared].scan;

    switch (ip.section) {
        case SPToolSectionStatus: {
            BOOL ok = [scan has:(SPToolchainComponent)ip.row];
            NSString *key = SPAtIndex(self.componentKeys, ip.row, @"未知组件");
            cell.textLabel.text = key;
            cell.imageView.image = [UIImage systemImageNamed:ok ? @"checkmark.circle.fill" : @"xmark.circle.fill"];
            cell.imageView.tintColor = ok ? [SPTheme success] : [SPTheme danger];
            NSString *path = [scan pathFor:(SPToolchainComponent)ip.row];
            cell.detailTextLabel.text = path.length
                ? [path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]
                : @"未找到";
            cell.detailTextLabel.textColor = ok ? [SPTheme textDim] : [SPTheme danger];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case SPToolSectionSDK: {
            // 固定三个候选（顺序：内置 → 较老 → 最新）。
            NSArray *cands = @[@"iPhoneOS16.5.sdk", @"iPhoneOS17.0.sdk", @"iPhoneOS26.5.sdk"];
            NSString *name = cands[ip.row];
            SPToolchain *tc = [SPToolchain shared];
            BOOL available = [[tc availableSDKs] containsObject:name];
            BOOL selected = [SPSettings.shared.defaultSDK isEqualToString:name] ||
                            (SPSettings.shared.defaultSDK.length == 0 && ip.row == 0);

            cell.textLabel.text = [name stringByDeletingPathExtension];
            if (available) {
                cell.imageView.image = [UIImage systemImageNamed:selected ? @"largecircle.fill.circle" : @"circle"];
                cell.imageView.tintColor = selected ? [SPTheme accent] : [SPTheme textDim];
                cell.detailTextLabel.text = selected ? @"当前使用" : (ip.row == 0 ? @"内置" : @"已安装");
                cell.detailTextLabel.textColor = [SPTheme textDim];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            } else {
                cell.imageView.image = [UIImage systemImageNamed:@"icloud.and.arrow.down"];
                cell.imageView.tintColor = [SPTheme info];
                cell.detailTextLabel.text = ip.row == 0 ? @"（不完整，点此重下）" : @"未安装 · 点此下载";
                cell.detailTextLabel.textColor = [SPTheme warn];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        }
        case SPToolSectionTarget: {
            NSArray *titles = @[@"默认构建目标", @"远程主机", @"GitHub 仓库", @"GitHub 分支"];
            cell.textLabel.text = titles[ip.row];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            SPSettings *s = SPSettings.shared;
            switch (ip.row) {
                case 0: cell.detailTextLabel.text = SPAtIndex(@[@"本机（真机编译）", @"远程设备", @"GitHub CI"], s.defaultTarget, @""); break;
                case 1: cell.detailTextLabel.text = s.sshHost.length
                    ? [NSString stringWithFormat:@"%@@%@:%ld", s.sshUser, s.sshHost, (long)s.sshPort] : @"未配置"; break;
                case 2: cell.detailTextLabel.text = s.githubRepo.length ? s.githubRepo : @"未配置"; break;
                default: cell.detailTextLabel.text = s.githubBranch ?: @"main"; break;
            }
            break;
        }
        case SPToolSectionDisplay: {
            NSArray *titles = @[@"编译时保持屏幕常亮", @"操作触感反馈", @"日志最多保留行数"];
            cell.textLabel.text = titles[ip.row];
            if (ip.row < 2) {
                UISwitch *sw = [[UISwitch alloc] init];
                sw.tag = 3000 + ip.row;
                sw.on = ip.row == 0 ? SPSettings.shared.keepScreenOn
                                    : [[NSUserDefaults standardUserDefaults] boolForKey:@"Workbench.haptics"];
                [sw addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)SPSettings.shared.maxLogLines];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        }
        default: {
            NSArray *titles = @[@"运行环境自检", @"打开 Rein 目录"];
            cell.textLabel.text = titles[ip.row];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.imageView.image = [UIImage systemImageNamed:ip.row == 0 ? @"stethoscope" : @"folder"];
            cell.imageView.tintColor = [SPTheme accent];
            break;
        }
    }
    return cell;
}

- (void)toggleSetting:(UISwitch *)sw {
    if (sw.tag == 3000) {
        SPSettings.shared.keepScreenOn = sw.isOn;
        [SPSettings.shared save];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"Workbench.haptics"];
    }
    [SPMotion hapticLight];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];

    if (ip.section == SPToolSectionSDK) {
        NSArray *cands = @[@"iPhoneOS16.5.sdk", @"iPhoneOS17.0.sdk", @"iPhoneOS26.5.sdk"];
        NSString *name = cands[ip.row];
        SPToolchain *tc = [SPToolchain shared];
        BOOL available = [[tc availableSDKs] containsObject:name];
        if (available) {
            SPSettings.shared.defaultSDK = name;
            [SPSettings.shared save];
            [tv reloadSections:[NSIndexSet indexSetWithIndex:SPToolSectionSDK]
             withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            [self downloadSDK:name];
        }
        return;
    }
    if (ip.section == SPToolSectionTarget) {
        [self editTargetAt:ip.row];
        return;
    }
    if (ip.section == SPToolSectionDisplay) {
        if (ip.row == 2) [self pickMaxLogLines];
        return;
    }
    if (ip.section == SPToolSectionAbout) {
        // 统一到自检页（页内自带「测试构建」动作）。
        // 以前这里有 runSelfCheck（跑脚本弹文本）、工具页有「测试构建」、
        // 我的页有「运行环境自检」—— 三个入口三套结论。
        if (ip.row == 0) {
            [self.navigationController pushViewController:[SPHealthViewController new] animated:YES];
        }
        else {
            SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
                initWithRootPath:[[SPToolchain shared] reinRoot] pickMode:NO fileFilters:nil onPick:nil];
            [self.navigationController pushViewController:b animated:YES];
        }
    }
}

#pragma mark - SDK 下载

/// 按需下载 17.0 / 26.5（16.5 若被损坏也允许重下）
- (void)downloadSDK:(NSString *)sdkName {
    SPComponent comp;
    if ([sdkName isEqualToString:@"iPhoneOS17.0.sdk"]) comp = SPComponentSDK17;
    else if ([sdkName isEqualToString:@"iPhoneOS26.5.sdk"]) comp = SPComponentSDK26;
    else {
        [self toast:@"16.5 是内置 SDK，通常无需下载"];
        return;
    }

    NSString *msg = [NSString stringWithFormat:@"下载 %@（约几十 MB）？\n\n将解压到内置工具链目录，并立刻可用于编译。",
                     sdkName];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"下载 SDK"
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self runSDKDownload:comp];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runSDKDownload:(SPComponent)comp {
    // 极简进度：导航栏转圈 + toast 结果（不新造进度页，沿用 downloader 进度回调）
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = [SPTheme accent];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    self.navigationItem.rightBarButtonItem = item;
    [spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [[SPToolchainDownloader shared] download:comp progress:^(CGFloat f, NSString *s) {
        // 进度不弹，只在完成时提示
    } completion:^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [spinner stopAnimating];
            UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self action:@selector(refreshAction)];
            self.navigationItem.rightBarButtonItem = refresh;
            [self refresh];
            if (ok) {
                [SPMotion hapticSuccess];
                [self toast:@"SDK 已安装，可在列表里选用"];
            } else {
                [SPMotion hapticError];
                [self toast:err.localizedDescription ?: @"下载失败，请检查网络"];
            }
        });
    }];
}

#pragma mark - 编辑设置

- (void)editTargetAt:(NSInteger)row {
    SPSettings *s = SPSettings.shared;
    if (row == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"默认构建目标" message:nil
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *titles = @[@"本机（真机编译）", @"远程设备（SSH）", @"GitHub Actions"];
        for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
            [a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                s.defaultTarget = i;
                [s save];
                [self.table reloadData];
            }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = self.view;
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    NSString *title = row == 1 ? @"远程 SSH" : (row == 2 ? @"GitHub 仓库" : @"GitHub 分支");
    NSString *message = row == 1 ? @"格式 user@host:port" : (row == 2 ? @"格式 owner/repo" : @"例如 main");
    NSString *current = row == 1
        ? (s.sshHost.length ? [NSString stringWithFormat:@"%@@%@:%ld", s.sshUser, s.sshHost, (long)s.sshPort] : @"")
        : (row == 2 ? s.githubRepo : s.githubBranch);

    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = current;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *text = a.textFields[0].text ?: @"";
        if (row == 1) {
            NSRange at = [text rangeOfString:@"@"];
            NSString *rest = text, *user = s.sshUser;
            if (at.location != NSNotFound) {
                user = [text substringToIndex:at.location];
                rest = [text substringFromIndex:at.location + 1];
            }
            NSRange colon = [rest rangeOfString:@":"];
            NSString *host = colon.location == NSNotFound ? rest : [rest substringToIndex:colon.location];
            NSInteger port = colon.location == NSNotFound ? 22 : [[rest substringFromIndex:colon.location + 1] integerValue];
            s.sshUser = user.length ? user : @"mobile";
            s.sshHost = host;
            s.sshPort = port > 0 ? port : 22;
        } else if (row == 2) {
            s.githubRepo = text;
        } else {
            s.githubBranch = text.length ? text : @"main";
        }
        [s save];
        [self.table reloadData];
        [SPMotion hapticSuccess];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickMaxLogLines {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"日志最多保留行数" message:@"行数越多越占内存"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in @[@2000, @5000, @10000, @20000]) {
        [a addAction:[UIAlertAction actionWithTitle:[n stringValue] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            SPSettings.shared.maxLogLines = n.integerValue;
            [SPSettings.shared save];
            [self.table reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 自检

- (void)runSelfCheck {
    NSMutableString *script = [NSMutableString string];
    [script appendString:@"echo '== 系统 =='; uname -a; id\n"];
    [script appendString:@"echo; echo '== Theos =='; echo \"THEOS=$THEOS\"; ls \"$THEOS\" 2>/dev/null | head\n"];
    [script appendString:@"echo; echo '== SDK =='; ls \"$THEOS/sdks\" 2>/dev/null\n"];
    [script appendString:@"echo; echo '== 关键工具 =='; for t in make ldid clang ld64 strip insert_dylib; do printf '%-14s' \"$t\"; command -v $t 2>/dev/null || echo '(缺失)'; done\n"];
    [script appendString:@"echo; echo '== make 版本 =='; make --version 2>&1 | head -2\n"];
    [script appendString:@"echo; echo '== PATH =='; echo \"$PATH\" | tr ':' '\\n'\n"];

    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"selfcheck.sh"];
    [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[@"THEOS"] = [[SPToolchain shared].scan pathFor:SPToolchainComponentTheos] ?: @"";
    env[@"PATH"] = [[SPToolchain shared] pathPrefixForProfile:[[SPToolchainProfile alloc] init]];

    NSDate *start = [NSDate date];
    __block NSMutableString *out = [NSMutableString string];
    __weak typeof(self) weakSelf = self;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = [SPTheme accent];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    self.navigationItem.rightBarButtonItem = item;
    [spinner startAnimating];

    SPSession *s = [[SPSession alloc] initWithEnvironment:env workingDirectory:NSHomeDirectory()];
    s.onLine = ^(NSString *line, SPLogLevel level) { [out appendString:line]; [out appendString:@"\n"]; };
    s.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        [spinner stopAnimating];
        UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self action:@selector(refreshAction)];
        self.navigationItem.rightBarButtonItem = refresh;

        NSString *text = [NSString stringWithFormat:@"环境自检  %@  退出码 %ld\n\n%@",
                          [SPUtil formatDuration:-[start timeIntervalSinceNow]], (long)r.exitCode, out];
        NSString *p = [[SPStore shared] persistLogText:text jobId:@"selfcheck"];
        SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:p];
        [self.navigationController pushViewController:e animated:YES];
    };
    s.timeout = 60;
    [s runShell:script];
}

#pragma mark - Toast

- (void)toast:(NSString *)text {
    if (!text.length) return;
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightMedium];
    l.textColor = [SPTheme text];
    l.backgroundColor = [SPTheme surface];
    l.textAlignment = NSTextAlignmentCenter;
    [SPTheme round:l radius:SPRadiusM];
    l.clipsToBounds = YES;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [l.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [l.heightAnchor constraintEqualToConstant:32],
        [l.widthAnchor constraintGreaterThanOrEqualToConstant:140],
    ]];
    l.alpha = 0;
    [SPMotion appear:^{ l.alpha = 1; }];
    [SPMotion disappear:^{ l.alpha = 0; } completion:^{ [l removeFromSuperview]; }];
}

@end
