//
//  RBToolchainViewController.m
//

#import "RBToolchainViewController.h"
#import "RBTheme.h"
#import "RBToolchain.h"
#import "RBStore.h"
#import "RBSession.h"
#import "RBCompat.h"
#import "RBEditorViewController.h"
#import "RBFileBrowserViewController.h"

@interface RBToolchainViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSString *> *components;
@property (nonatomic, strong) NSArray<NSString *> *componentKeys;
@end

@implementation RBToolchainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RBTheme background];
    self.title = @"工具链";
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    self.componentKeys = @[@"Theos", @"SDK", @"Darwin 工具", @"OLLVM", @"逆向工具", @"Python", @"Node", @"SSH"];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [RBTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [RBTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"重新扫描" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(refreshAction)];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    [[RBToolchain shared] rescan];
    [self.table reloadData];
}

- (void)refreshAction {
    [self refresh];
    UIWindow *w = self.view.window;
    UILabel *toast = [[UILabel alloc] init];
    toast.text = @"已重新扫描";
    toast.font = [RBTheme uiFont:12 weight:UIFontWeightMedium];
    toast.textColor = [RBTheme background];
    toast.backgroundColor = [RBTheme accent];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [w addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:w.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [toast.widthAnchor constraintEqualToConstant:140],
        [toast.heightAnchor constraintEqualToConstant:32],
    ]];
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ toast.alpha = 0; }
                     completion:^(BOOL done) { [toast removeFromSuperview]; }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 5; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"探测结果", @"SDK", @"构建目标", @"日志 / 显示", @"关于"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        NSArray *remedies = [[RBToolchain shared].scan remedies];
        return remedies.count ? [remedies componentsJoinedByString:@"\n"] : nil;
    }
    if (s == 3) return @"屏幕常亮在编译期间会自动开启，编译结束后恢复。";
    if (s == 4) return nil;
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case 0: return RBToolchainComponentCount;
        case 1: return MAX(1, [[RBToolchain shared] availableSDKs].count);
        case 2: return 4;
        case 3: return 3;
        case 4: return 3;
    }
    return 0;
}

- (void)styleCell:(UITableViewCell *)cell {
    cell.backgroundColor = [RBTheme surface];
    cell.textLabel.textColor = [RBTheme text];
    cell.textLabel.font = [RBTheme uiFont:14 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [RBTheme textDim];
    cell.detailTextLabel.font = [RBTheme monoFont:10];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [self styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    RBToolchainScan *scan = [RBToolchain shared].scan;

    if (ip.section == 0) {
        NSString *key = self.componentKeys[ip.row];
        BOOL ok = [scan has:(RBToolchainComponent)ip.row];
        NSString *path = [scan pathFor:(RBToolchainComponent)ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", ok ? @"✅" : @"⛔️", key];
        cell.detailTextLabel.text = path.length ? [path stringByReplacingOccurrencesOfString:NSHomeDirectory()
                                                                                 withString:@"~"] : @"未找到";
        cell.detailTextLabel.textColor = ok ? [RBTheme textDim] : [RBTheme danger];
    } else if (ip.section == 1) {
        NSArray *sdks = [[RBToolchain shared] availableSDKs];
        if (!sdks.count) {
            cell.textLabel.text = @"未发现 SDK";
            cell.detailTextLabel.text = @"到 Rein 的 sdks-store 复制一份";
            cell.detailTextLabel.textColor = [RBTheme danger];
        } else {
            NSString *sdk = sdks[ip.row];
            cell.textLabel.text = sdk;
            cell.detailTextLabel.text = RBSettings.shared.defaultSDK.length ? @"默认 SDK" : @"";
            BOOL selected = [sdk isEqualToString:RBSettings.shared.defaultSDK] ||
                            (RBSettings.shared.defaultSDK.length == 0 && ip.row == sdks.count - 1);
            cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.tintColor = [RBTheme accent];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else if (ip.section == 2) {
        NSArray *labels = @[@"默认构建目标", @"远程主机", @"GitHub 仓库", @"GitHub 分支"];
        cell.textLabel.text = labels[ip.row];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        RBSettings *s = RBSettings.shared;
        switch (ip.row) {
            case 0: cell.detailTextLabel.text = @[@"本机（真机编译）", @"远程设备", @"GitHub CI"][s.defaultTarget]; break;
            case 1: cell.detailTextLabel.text = s.sshHost.length ? [NSString stringWithFormat:@"%@@%@:%ld", s.sshUser, s.sshHost, (long)s.sshPort] : @"未配置"; break;
            case 2: cell.detailTextLabel.text = s.githubRepo.length ? s.githubRepo : @"未配置"; break;
            case 3: cell.detailTextLabel.text = s.githubBranch ?: @"main"; break;
        }
    } else if (ip.section == 3) {
        NSArray *labels = @[@"编译时保持屏幕常亮", @"编译结束振动反馈", @"日志最大行数"];
        cell.textLabel.text = labels[ip.row];
        if (ip.row < 2) {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = ip.row == 0 ? RBSettings.shared.keepScreenOn : RBSettings.shared.hapticsOnBuildDone;
            sw.onTintColor = [RBTheme accent];
            sw.tag = 1000 + ip.row;
            [sw addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)RBSettings.shared.maxLogLines];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else {
        NSArray *labels = @[@"查看本机环境自检", @"打开 Rein 目录", @"关于 ReinBuild"];
        cell.textLabel.text = labels[ip.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)toggleSetting:(UISwitch *)sw {
    BOOL on = sw.isOn;
    if (sw.tag == 1000) RBSettings.shared.keepScreenOn = on;
    else RBSettings.shared.hapticsOnBuildDone = on;
    [RBSettings.shared save];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        NSArray *sdks = [[RBToolchain shared] availableSDKs];
        if (ip.row < sdks.count) {
            RBSettings.shared.defaultSDK = sdks[ip.row];
            [RBSettings.shared save];
            [self.table reloadData];
        }
        return;
    }
    if (ip.section == 2) {
        [self editSettingAt:ip.row];
        return;
    }
    if (ip.section == 3 && ip.row == 2) {
        [self pickMaxLogLines];
        return;
    }
    if (ip.section == 4) {
        switch (ip.row) {
            case 0: [self runSelfCheck]; break;
            case 1: {
                RBFileBrowserViewController *b = [[RBFileBrowserViewController alloc]
                    initWithRootPath:[[RBToolchain shared] reinRoot] pickMode:NO fileFilters:nil onPick:nil];
                [self.navigationController pushViewController:b animated:YES];
                break;
            }
            case 2: [self showAbout]; break;
        }
    }
}

- (void)editSettingAt:(NSInteger)row {
    RBSettings *s = RBSettings.shared;
    if (row == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"默认构建目标"
            message:@"本机：直接在 iPhone 上 make；远程：ssh 到另一台越狱设备；CI：交给 GitHub Actions"
            preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *titles = @[@"本机（真机编译）", @"远程设备", @"GitHub CI"];
        for (NSInteger i = 0; i < titles.count; i++) {
            [a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                s.defaultTarget = i; [s save]; [self.table reloadData];
            }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = self.view;
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    NSString *title = row == 1 ? @"远程 SSH" : (row == 2 ? @"GitHub 仓库" : @"GitHub 分支");
    NSString *message = row == 1 ? @"格式：user@host:port" : (row == 2 ? @"格式：owner/repo" : @"默认 main");
    NSString *current = row == 1
        ? (s.sshHost.length ? [NSString stringWithFormat:@"%@@%@:%ld", s.sshUser, s.sshHost, (long)s.sshPort] : @"")
        : (row == 2 ? s.githubRepo : s.githubBranch);
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = current;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *text = a.textFields[0].text;
        if (row == 1) {
            NSRange at = [text rangeOfString:@"@"];
            NSString *rest = text, *user = s.sshUser;
            if (at.location != NSNotFound) {
                user = [text substringToIndex:at.location];
                rest = [text substringFromIndex:at.location + 1];
            }
            NSRange colon = [rest rangeOfString:@":"];
            NSString *host = rest;
            NSInteger port = 22;
            if (colon.location != NSNotFound) {
                host = [rest substringToIndex:colon.location];
                port = [[rest substringFromIndex:colon.location + 1] integerValue];
            }
            s.sshUser = user; s.sshHost = host; s.sshPort = port;
        } else if (row == 2) {
            s.githubRepo = text;
        } else {
            s.githubBranch = text;
        }
        [s save];
        [self.table reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickMaxLogLines {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"日志最大行数" message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in @[@2000, @5000, @10000, @20000]) {
        [a addAction:[UIAlertAction actionWithTitle:[n stringValue] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            RBSettings.shared.maxLogLines = n.integerValue;
            [RBSettings.shared save];
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
    [script appendString:@"echo; echo '== Rein 目录 =='; ls -d \"$RB_REIN_ROOT\" 2>/dev/null\n"];
    [script appendString:@"echo; echo '== Theos =='; echo \"THEOS=$THEOS\"; ls \"$THEOS\" 2>/dev/null | head\n"];
    [script appendString:@"echo; echo '== SDK =='; ls \"$THEOS/sdks\" 2>/dev/null\n"];
    [script appendString:@"echo; echo '== make/ldid =='; command -v make ldid clang ld64 strip 2>/dev/null\n"];
    [script appendString:@"echo; echo '== make 版本 =='; make --version 2>&1 | head -2\n"];
    [script appendString:@"echo; echo '== PATH =='; echo \"$PATH\" | tr ':' '\\n'\n"];

    NSString *path = [[[RBStore shared] logsDirectory] stringByAppendingPathComponent:@"selfcheck.sh"];
    [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    UIAlertController *busy = [UIAlertController alertControllerWithTitle:@"自检中…" message:nil
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:busy animated:YES completion:nil];

    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[@"RB_REIN_ROOT"] = [[RBToolchain shared] reinRoot] ?: @"";
    NSString *theos = [RBToolchain shared].scan.pathFor(RBToolchainComponentTheos);
    if (theos) env[@"THEOS"] = theos;
    env[@"PATH"] = [[RBToolchain shared] pathPrefixForProfile:[[RBToolchainProfile alloc] init]];

    NSDate *start = [NSDate date];
    __block NSMutableString *out = [NSMutableString string];
    RBSession *s = [[RBSession alloc] initWithEnvironment:env workingDirectory:NSHomeDirectory()];
    s.onLine = ^(NSString *line, RBLogLevel level) { [out appendString:line]; [out appendString:@"\n"]; };
    s.onFinish = ^(RBCommandResult *r) {
        [busy dismissViewControllerAnimated:YES completion:^{
            NSString *text = [NSString stringWithFormat:@"%@@%@  %@\n\n%@",
                              RBSettings.shared.sshUser ?: @"", @"selfcheck",
                              [RBUtil formatDuration:-[start timeIntervalSinceNow]], out];
            NSString *p = [[RBStore shared] persistLogText:text jobId:@"selfcheck"];
            RBEditorViewController *e = [[RBEditorViewController alloc] initWithFilePath:p];
            [self.navigationController pushViewController:e animated:YES];
        }];
    };
    s.timeout = 60;
    [s runShell:script];
}

- (void)showAbout {
    NSString *msg = [NSString stringWithFormat:
        @"ReinBuild %@\n构建标识：%@\n构建时间：%@\n\n"
        @"一个参考 Rein 的可视化编译工具：\n"
        @"• Theos / Logos 项目一键编译\n"
        @"• OLLVM（Arkari LLVM 16）混淆\n"
        @"• 逆向工具（radare2 / mt-macho / 注入 dylib）\n"
        @"• 本机 / 远程 / GitHub CI 三种构建目标\n\n"
        @"开源协议 MIT",
        RBVersion.shared.semver, RBVersion.shared.gitDescribe, RBVersion.shared.builtAt];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"关于 ReinBuild" message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
