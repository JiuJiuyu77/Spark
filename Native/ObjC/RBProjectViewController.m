//
//  RBProjectViewController.m
//

#import "RBProjectViewController.h"
#import "RBTheme.h"
#import "RBStore.h"
#import "RBBuilder.h"
#import "RBConsoleViewController.h"
#import "RBEditorViewController.h"
#import "RBFileBrowserViewController.h"
#import "RBToolchain.h"
#import "RBCompat.h"

@interface RBProjectViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) RBProject *project;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) RBToolchainProfile *profile;
@property (nonatomic, strong) NSError *profileError;
@property (nonatomic, strong) UIButton *buildButton;
@property (nonatomic, strong) UILabel *headerTitle;
@property (nonatomic, strong) UILabel *headerSubtitle;
@end

@implementation RBProjectViewController

- (instancetype)initWithProject:(RBProject *)project {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _project = project;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RBTheme background];
    self.title = self.project.name;
    [self refreshProfile];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [RBTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [RBTheme separator];
    self.table.tintColor = [RBTheme accent];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self setupFooter];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshProfile];
    [self.table reloadData];
    [self updateFooter];
}

- (void)refreshProfile {
    NSString *sdk = RBSettings.shared.defaultSDK.length ? RBSettings.shared.defaultSDK : nil;
    self.profile = [[RBToolchain shared] localProfileWithSDK:sdk error:&self.profileError];
    if (!self.profile && RBSettings.shared.sshHost.length) {
        // 本机没工具链但有远程，则退化成远程 profile
        self.profile = [[RBToolchain shared] remoteProfileWithHost:RBSettings.shared.sshHost
                                                              user:RBSettings.shared.sshUser
                                                              port:RBSettings.shared.sshPort
                                                               sdk:sdk];
        self.profileError = nil;
    }
}

#pragma mark - 底部构建按钮

- (void)setupFooter {
    UIView *footer = [[UIView alloc] init];
    footer.backgroundColor = [RBTheme background];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];

    self.buildButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.buildButton setTitle:@"▶  编译" forState:UIControlStateNormal];
    [RBTheme stylePrimaryButton:self.buildButton];
    self.buildButton.titleLabel.font = [RBTheme uiFont:16 weight:UIFontWeightBold];
    [self.buildButton addTarget:self action:@selector(buildTapped) forControlEvents:UIControlEventTouchUpInside];
    self.buildButton.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:self.buildButton];

    self.headerSubtitle = [[UILabel alloc] init];
    self.headerSubtitle.font = [RBTheme monoFont:10];
    self.headerSubtitle.textColor = [RBTheme textDim];
    self.headerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:self.headerSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.buildButton.topAnchor constraintEqualToAnchor:footer.topAnchor constant:8],
        [self.buildButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.buildButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.buildButton.heightAnchor constraintEqualToConstant:48],

        [self.headerSubtitle.topAnchor constraintEqualToAnchor:self.buildButton.bottomAnchor constant:6],
        [self.headerSubtitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.headerSubtitle.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.headerSubtitle.bottomAnchor constraintEqualToAnchor:footer.safeAreaLayoutGuide.bottomAnchor constant:-6],
    ]];

    // table 让出底部
    [NSLayoutConstraint activateConstraints:@[
        [self.table.bottomAnchor constraintEqualToAnchor:footer.topAnchor],
    ]];
}

- (void)updateFooter {
    if (self.profileError) {
        self.headerSubtitle.text = self.profileError.localizedDescription;
        self.headerSubtitle.textColor = [RBTheme danger];
        self.buildButton.alpha = 0.5;
    } else if (self.profile) {
        self.headerSubtitle.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                                    self.profile.name,
                                    self.profile.sdkName.length ? self.profile.sdkName : @"自动 SDK",
                                    [self.project.options displaySummary]];
        self.headerSubtitle.textColor = [RBTheme textDim];
        self.buildButton.alpha = 1.0;
    }
}

- (void)buildTapped {
    if (!self.profile) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"工具链不可用"
            message:self.profileError.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"去工具链页" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [self.navigationController popToRootViewControllerAnimated:YES];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"RBOpenToolchainTab" object:nil];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [[RBStore shared] saveOptions:self.project.options forProjectPath:self.project.path];
    RBConsoleViewController *console = [[RBConsoleViewController alloc] initWithProject:self.project profile:self.profile];
    console.autoStart = YES;
    console.onJobFinished = ^(RBJob *job) {
        if (self.onProjectUpdated) self.onProjectUpdated(self.project);
    };
    [self.navigationController pushViewController:console animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"项目", @"构建选项", @"混淆（OLLVM）", @"快捷操作"][s];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case 0: return 4;
        case 1: return 7;
        case 2: return 3;
        case 3: return 5;
    }
    return 0;
}

- (void)styleCell:(UITableViewCell *)cell {
    cell.backgroundColor = [RBTheme surface];
    cell.textLabel.textColor = [RBTheme text];
    cell.textLabel.font = [RBTheme uiFont:14 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [RBTheme textDim];
    cell.detailTextLabel.font = [RBTheme monoFont:11];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    [self styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    RBBuildOptions *o = self.project.options;

    if (ip.section == 0) {
        NSArray *labels = @[@"类型", @"包标识", @"版本", @"源码文件"];
        cell.textLabel.text = labels[ip.row];
        switch (ip.row) {
            case 0: cell.detailTextLabel.text = [self.project kindString]; break;
            case 1: cell.detailTextLabel.text = self.project.packageId ?: @"—"; break;
            case 2: cell.detailTextLabel.text = self.project.version ?: @"—"; break;
            case 3: cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 个", (unsigned long)self.project.sourceFiles.count]; break;
        }
        cell.selectionStyle = ip.row == 3 ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else if (ip.section == 1) {
        switch (ip.row) {
            case 0:
                cell.textLabel.text = @"架构";
                cell.detailTextLabel.text = @[@"arm64", @"arm64e", @"arm64 + arm64e"][o.arch];
                break;
            case 1:
                cell.textLabel.text = @"包格式";
                cell.detailTextLabel.text = @[@"deb（传统）", @"deb（rootless）", @".app", @".tipa"][o.format];
                break;
            case 2:
                cell.textLabel.text = @"编译配置";
                cell.detailTextLabel.text = o.debug ? @"Debug (-O0 -g)" : @"Release (-O2)";
                break;
            case 3:
                cell.textLabel.text = @"构建前清理";
                [self addSwitchTo:cell on:o.cleanBeforeBuild action:@selector(cleanToggled:)];
                break;
            case 4:
                cell.textLabel.text = @"并行编译（-j）";
                [self addSwitchTo:cell on:o.parallel action:@selector(parallelToggled:)];
                break;
            case 5:
                cell.textLabel.text = @"补签（ldid -S）";
                [self addSwitchTo:cell on:o.signWithLdid action:@selector(signToggled:)];
                break;
            case 6:
                cell.textLabel.text = @"撤销符号表（strip）";
                [self addSwitchTo:cell on:o.strip action:@selector(stripToggled:)];
                break;
        }
    } else if (ip.section == 2) {
        switch (ip.row) {
            case 0:
                cell.textLabel.text = @"启用 OLLVM";
                [self addSwitchTo:cell on:o.useOLLVM action:@selector(ollvmToggled:)];
                break;
            case 1:
                cell.textLabel.text = @"混淆强度";
                cell.detailTextLabel.text = @[@"无", @"轻度", @"均衡", @"强力", @"自定义"][o.obfuscation];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 2:
                cell.textLabel.text = @"启用的 Pass";
                cell.detailTextLabel.text = o.obfuscationPasses.count ? [o.obfuscationPasses componentsJoinedByString:@" + "] : @"—";
                break;
        }
    } else {
        NSArray *labels = @[@"查看源码", @"查看 Makefile", @"构建历史", @"复制编译命令", @"打开构建目录"];
        cell.textLabel.text = labels[ip.row];
        if (ip.row == 2) cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条",
                                                      (unsigned long)[[RBStore shared] buildHistory].count];
    }
    return cell;
}

- (void)addSwitchTo:(UITableViewCell *)cell on:(BOOL)on action:(SEL)action {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    sw.onTintColor = [RBTheme accent];
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)cleanToggled:(UISwitch *)sw { self.project.options.cleanBeforeBuild = sw.isOn; [self persist]; }
- (void)parallelToggled:(UISwitch *)sw { self.project.options.parallel = sw.isOn; [self persist]; }
- (void)signToggled:(UISwitch *)sw { self.project.options.signWithLdid = sw.isOn; [self persist]; }
- (void)stripToggled:(UISwitch *)sw { self.project.options.strip = sw.isOn; [self persist]; }

- (void)ollvmToggled:(UISwitch *)sw {
    self.project.options.useOLLVM = sw.isOn;
    if (!sw.isOn) self.project.options.obfuscation = RBObfuscationNone;
    else if (self.project.options.obfuscation == RBObfuscationNone) self.project.options.obfuscation = RBObfuscationLight;
    [self persist];
}

- (void)persist {
    [[RBStore shared] saveOptions:self.project.options forProjectPath:self.project.path];
    [self.table reloadData];
    [self updateFooter];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 3) { [self openFile:self.project.sourceFiles.firstObject]; return; }
    if (ip.section == 1) {
        if (ip.row == 0) [self pickArch];
        else if (ip.row == 1) [self pickFormat];
        else if (ip.row == 2) { self.project.options.debug = !self.project.options.debug; [self persist]; }
        return;
    }
    if (ip.section == 2) {
        if (ip.row == 1) [self pickObfuscation];
        else if (ip.row == 2) [self pickPasses];
        return;
    }
    if (ip.section == 3) {
        switch (ip.row) {
            case 0: [self openFile:self.project.sourceFiles.firstObject]; break;
            case 1: [self openFile:self.project.makefilePath]; break;
            case 2: [self showHistory]; break;
            case 3: [self copyBuildCommand]; break;
            case 4: [self openProjectTree]; break;
        }
    }
}

- (void)openFile:(NSString *)path {
    if (!path.length) return;
    RBEditorViewController *e = [[RBEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:e animated:YES];
}

- (void)openProjectTree {
    RBFileBrowserViewController *b = [[RBFileBrowserViewController alloc] initWithRootPath:self.project.path
                                                                              pickMode:NO fileFilters:nil onPick:nil];
    [self.navigationController pushViewController:b animated:YES];
}

- (void)pickArch {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"架构" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < 3; i++) {
        [a addAction:[UIAlertAction actionWithTitle:@[@"arm64", @"arm64e", @"arm64 + arm64e"][i]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            self.project.options.arch = i; [self persist];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickFormat {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"包格式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"deb（传统 rootful）", @"deb（rootless）", @".app", @".tipa"];
    for (NSInteger i = 0; i < titles.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            self.project.options.format = i; [self persist];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickObfuscation {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"混淆强度"
        message:@"对应 Rein 的 Arkari LLVM passes 组合" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"无", @"轻度（indbr + cse）", @"均衡（indbr + icall + cse）",
                        @"强力（全部 5 个 pass）", @"自定义"];
    for (NSInteger i = 0; i < titles.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            self.project.options.obfuscation = i;
            if (i == RBObfuscationNone) self.project.options.useOLLVM = NO;
            else self.project.options.useOLLVM = YES;
            [self persist];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickPasses {
    NSArray *passes = @[@"indbr（间接跳转）", @"icall（间接调用）", @"indgv（间接全局）",
                        @"cse（字符串加密）", @"cff（控制流平坦化）"];
    NSArray *ids = @[@"indbr", @"icall", @"indgv", @"cse", @"cff"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"选择 OLLVM Pass"
        message:@"多选，保存后立即生效" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < passes.count; i++) {
        BOOL on = [self.project.options.obfuscationPasses containsObject:ids[i]];
        NSString *title = [NSString stringWithFormat:@"%@ %@", on ? @"✓" : @"○", passes[i]];
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSMutableArray *ps = [self.project.options.obfuscationPasses mutableCopy] ?: [NSMutableArray array];
            if (on) [ps removeObject:ids[i]]; else [ps addObject:ids[i]];
            self.project.options.obfuscationPasses = ps;
            self.project.options.obfuscation = RBObfuscationCustom;
            self.project.options.useOLLVM = ps.count > 0;
            [self persist];
            // 连续多选：再弹一次
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pickPasses];
            });
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)copyBuildCommand {
    NSString *script = [RBBuilder scriptForProject:self.project options:self.project.options
                                           profile:self.profile ?: [[RBToolchain shared] ciProfileWithSDK:nil]
                                        backupPath:nil];
    UIPasteboard.generalPasteboard.string = script;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已复制构建脚本"
        message:@"可以粘贴到终端或提交到 CI" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showHistory {
    NSArray *records = [[RBStore shared] buildHistory];
    NSMutableString *text = [NSMutableString string];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm";
    for (NSDictionary *r in records) {
        if (![r[@"project"] isEqual:self.project.path]) continue;
        NSInteger state = [r[@"state"] integerValue];
        NSString *mark = state == 2 ? @"✓" : (state == 1 ? @"▶" : (state == 4 ? @"⏹" : @"✗"));
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:[r[@"started"] doubleValue]];
        [text appendFormat:@"%@ %@  %@  %@\n", mark, [f stringFromDate:d], r[@"summary"], r[@"name"]];
    }
    if (!text.length) text = [NSMutableString stringWithString:@"还没有构建记录"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"构建历史"
        message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
