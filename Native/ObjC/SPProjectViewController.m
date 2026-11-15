//
//  SPProjectViewController.m
//  单个项目的构建面板 —— HIG：分组列表（信息 / 选项 / 混淆 / 操作）+ 底部主操作按钮
//

#import "SPProjectViewController.h"
#import "SPTheme.h"
#import "SPStore.h"
#import "SPBuilder.h"
#import "SPConsoleViewController.h"
#import "SPEditorViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchain.h"
#import "SPCompat.h"
#import "SPModels.h"

typedef NS_ENUM(NSInteger, SPProjectSection) {
    SPProjectSectionInfo = 0,
    SPProjectSectionOptions,
    SPProjectSectionObfuscation,
    SPProjectSectionActions,
    SPProjectSectionCount,
};

@interface SPProjectViewController ()
@property (nonatomic, strong) SPProject *project;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) SPToolchainProfile *profile;
@property (nonatomic, strong) NSError *profileError;
@property (nonatomic, strong) UIButton *buildButton;
@property (nonatomic, strong) UILabel *footerHint;
@property (nonatomic, strong) UIView *footer;
@end

@implementation SPProjectViewController

- (instancetype)initWithProject:(SPProject *)project {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _project = project;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = self.project.name;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self refreshProfile];
    [self buildFooter];
    [self buildTable];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshProfile];
    [self.table reloadData];
    [self updateFooter];
}

- (void)refreshProfile {
    NSString *sdk = SPSettings.shared.defaultSDK.length ? SPSettings.shared.defaultSDK : nil;
    self.profile = [[SPToolchain shared] localProfileWithSDK:sdk error:&self.profileError];
    if (!self.profile && SPSettings.shared.sshHost.length) {
        self.profile = [[SPToolchain shared] remoteProfileWithHost:SPSettings.shared.sshHost
                                                              user:SPSettings.shared.sshUser
                                                              port:SPSettings.shared.sshPort
                                                               sdk:sdk];
        self.profileError = nil;
    }
}

#pragma mark - 布局

- (void)buildFooter {
    UIView *footer = [[UIView alloc] init];
    footer.backgroundColor = [SPTheme background];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];

    self.buildButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.buildButton setTitle:@"编译" forState:UIControlStateNormal];
    self.buildButton.configuration.image = [UIImage systemImageNamed:@"play.fill"];
    self.buildButton.configuration.imagePadding = 8;
    [SPTheme stylePrimaryButton:self.buildButton];
    self.buildButton.configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *out = [incoming mutableCopy];
        out[NSFontAttributeName] = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightSemibold];
        return out;
    };
    [self.buildButton addTarget:self action:@selector(buildTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.buildButton addTarget:self action:@selector(pressDown:) forControlEvents:UIControlEventTouchDown];
    [self.buildButton addTarget:self action:@selector(pressUp:) forControlEvents:UIControlEventTouchUpInside];
    self.buildButton.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:self.buildButton];

    self.footerHint = [[UILabel alloc] init];
    self.footerHint.font = [SPTheme caption];
    self.footerHint.textColor = [SPTheme textDim];
    self.footerHint.numberOfLines = 2;
    self.footerHint.textAlignment = NSTextAlignmentCenter;
    self.footerHint.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:self.footerHint];

    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.buildButton.topAnchor constraintEqualToAnchor:footer.topAnchor constant:8],
        [self.buildButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.buildButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.buildButton.heightAnchor constraintEqualToConstant:50],

        [self.footerHint.topAnchor constraintEqualToAnchor:self.buildButton.bottomAnchor constant:6],
        [self.footerHint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.footerHint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.footerHint.bottomAnchor constraintEqualToAnchor:footer.safeAreaLayoutGuide.bottomAnchor constant:-6],
    ]];
    self.footer = footer;
}

- (void)buildTable {
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.footer.topAnchor],
    ]];
}

- (void)pressDown:(UIButton *)b { [SPMotion pressDown:b]; }
- (void)pressUp:(UIButton *)b { [SPMotion pressUp:b]; }

- (void)updateFooter {
    if (self.profileError) {
        self.footerHint.text = self.profileError.localizedDescription;
        self.footerHint.textColor = [SPTheme danger];
        self.buildButton.enabled = NO;
    } else if (self.profile) {
        self.footerHint.text = [NSString stringWithFormat:@"%@ · %@", self.profile.name,
                                self.profile.sdkName.length ? self.profile.sdkName : @"自动选择 SDK"];
        self.footerHint.textColor = [SPTheme textDim];
        self.buildButton.enabled = YES;
    }
}

- (void)buildTapped {
    if (!self.profile) {
        [self presentToolchainHint];
        return;
    }
    [SPMotion hapticLight];
    [[SPStore shared] saveOptions:self.project.options forProjectPath:self.project.path];
    SPConsoleViewController *console = [[SPConsoleViewController alloc] initWithProject:self.project profile:self.profile];
    console.autoStart = YES;
    console.onJobFinished = ^(SPJob *job) {
        if (self.onProjectUpdated) self.onProjectUpdated(self.project);
    };
    [self.navigationController pushViewController:console animated:YES];
}

- (void)presentToolchainHint {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"工具链不可用"
        message:self.profileError.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"去工具链页" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        [self.navigationController popToRootViewControllerAnimated:YES];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SPOpenToolchainTab" object:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SPProjectSectionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SPProjectSectionInfo: return @"工程信息";
        case SPProjectSectionOptions: return @"构建选项";
        case SPProjectSectionObfuscation: return @"OLLVM 混淆";
        default: return @"操作";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SPProjectSectionObfuscation && self.project.options.useOLLVM) {
        return [NSString stringWithFormat:@"当前启用：%@", [self.project.options.obfuscationPasses componentsJoinedByString:@" + "] ?: @"无"];
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SPProjectSectionInfo: return 4;
        case SPProjectSectionOptions: return 7;
        case SPProjectSectionObfuscation: return 3;
        default: return 5;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    SPBuildOptions *o = self.project.options;

    switch (ip.section) {
        case SPProjectSectionInfo: {
            NSArray *titles = @[@"类型", @"包标识", @"版本", @"源文件"];
            cell.textLabel.text = titles[ip.row];
            switch (ip.row) {
                case 0: cell.detailTextLabel.text = [self.project kindString]; break;
                case 1: cell.detailTextLabel.text = self.project.packageId ?: @"—"; break;
                case 2: cell.detailTextLabel.text = self.project.version ?: @"—"; break;
                default: cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 个", (unsigned long)self.project.sourceFiles.count]; break;
            }
            if (ip.row == 3) { cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault; }
            break;
        }
        case SPProjectSectionOptions: {
            switch (ip.row) {
                case 0: cell.textLabel.text = @"架构"; cell.detailTextLabel.text = @[@"arm64", @"arm64e", @"arm64 + arm64e"][o.arch];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault; break;
                case 1: cell.textLabel.text = @"包格式"; cell.detailTextLabel.text = @[@"deb（传统）", @"deb（rootless）", @".app", @".tipa"][o.format];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault; break;
                case 2: cell.textLabel.text = @"编译配置"; cell.detailTextLabel.text = o.debug ? @"Debug" : @"Release";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault; break;
                case 3: cell.textLabel.text = @"构建前清理"; [self addSwitch:cell on:o.cleanBeforeBuild tag:4000]; break;
                case 4: cell.textLabel.text = @"并行编译"; [self addSwitch:cell on:o.parallel tag:4001]; break;
                case 5: cell.textLabel.text = @"ldid 补签"; [self addSwitch:cell on:o.signWithLdid tag:4002]; break;
                default: cell.textLabel.text = @"撤销符号表"; [self addSwitch:cell on:o.strip tag:4003]; break;
            }
            break;
        }
        case SPProjectSectionObfuscation: {
            switch (ip.row) {
                case 0: cell.textLabel.text = @"启用 OLLVM"; [self addSwitch:cell on:o.useOLLVM tag:4004]; break;
                case 1: cell.textLabel.text = @"混淆强度"; cell.detailTextLabel.text = @[@"无", @"轻度", @"均衡", @"强力", @"自定义"][o.obfuscation];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault; break;
                default: cell.textLabel.text = @"启用的 Pass";
                    cell.detailTextLabel.text = o.obfuscationPasses.count ? [o.obfuscationPasses componentsJoinedByString:@" + "] : @"—";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault; break;
            }
            break;
        }
        default: {
            NSArray *titles = @[@"查看源码", @"查看 Makefile", @"构建历史", @"复制编译命令", @"浏览工程目录"];
            cell.textLabel.text = titles[ip.row];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            if (ip.row == 2) cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条",
                (unsigned long)[[SPStore shared] buildHistory].count];
            break;
        }
    }
    return cell;
}

- (void)addSwitch:(UITableViewCell *)cell on:(BOOL)on tag:(NSInteger)tag {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)switchChanged:(UISwitch *)sw {
    SPBuildOptions *o = self.project.options;
    switch (sw.tag) {
        case 4000: o.cleanBeforeBuild = sw.isOn; break;
        case 4001: o.parallel = sw.isOn; break;
        case 4002: o.signWithLdid = sw.isOn; break;
        case 4003: o.strip = sw.isOn; break;
        case 4004:
            o.useOLLVM = sw.isOn;
            if (!sw.isOn) o.obfuscation = SPObfuscationNone;
            else if (o.obfuscation == SPObfuscationNone) o.obfuscation = SPObfuscationLight;
            break;
    }
    [self persist];
    [SPMotion hapticLight];
}

- (void)persist {
    [[SPStore shared] saveOptions:self.project.options forProjectPath:self.project.path];
    [self.table reloadData];
    [self updateFooter];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];

    if (ip.section == SPProjectSectionInfo && ip.row == 3) { [self openFile:self.project.sourceFiles.firstObject]; return; }
    if (ip.section == SPProjectSectionOptions) {
        if (ip.row == 0) [self pickFrom:@[@"arm64", @"arm64e", @"arm64 + arm64e"] title:@"架构" apply:^(NSInteger i) {
            self.project.options.arch = i;
        }];
        else if (ip.row == 1) [self pickFrom:@[@"deb（传统）", @"deb（rootless）", @".app", @".tipa"] title:@"包格式" apply:^(NSInteger i) {
            self.project.options.format = i;
        }];
        else if (ip.row == 2) { self.project.options.debug = !self.project.options.debug; [self persist]; }
        return;
    }
    if (ip.section == SPProjectSectionObfuscation) {
        if (ip.row == 1) [self pickFrom:@[@"无", @"轻度（indbr + cse）", @"均衡（indbr + icall + cse）",
                                         @"强力（全部 5 个 pass）", @"自定义"] title:@"混淆强度" apply:^(NSInteger i) {
            self.project.options.obfuscation = i;
            self.project.options.useOLLVM = i != SPObfuscationNone;
        }];
        else if (ip.row == 2) [self pickPasses];
        return;
    }
    switch (ip.row) {
        case 0: [self openFile:self.project.sourceFiles.firstObject]; break;
        case 1: [self openFile:self.project.makefilePath]; break;
        case 2: [self showHistory]; break;
        case 3: [self copyBuildCommand]; break;
        default: {
            SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:self.project.path
                                                                                     pickMode:NO fileFilters:nil onPick:nil];
            [self.navigationController pushViewController:b animated:YES];
            break;
        }
    }
}

- (void)pickFrom:(NSArray<NSString *> *)titles title:(NSString *)title apply:(void (^)(NSInteger))apply {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            apply(i);
            [self persist];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickPasses {
    NSArray *names = @[@"indbr（间接跳转）", @"icall（间接调用）", @"indgv（间接全局）",
                       @"cse（字符串加密）", @"cff（控制流平坦化）"];
    NSArray *ids = @[@"indbr", @"icall", @"indgv", @"cse", @"cff"];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"OLLVM Pass"
        message:@"可多选，选完点完成" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)ids.count; i++) {
        BOOL on = [self.project.options.obfuscationPasses containsObject:ids[i]];
        NSString *title = [NSString stringWithFormat:@"%@ %@", on ? @"✓" : @"○", names[i]];
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSMutableArray *ps = [self.project.options.obfuscationPasses mutableCopy] ?: [NSMutableArray array];
            if (on) [ps removeObject:ids[i]]; else [ps addObject:ids[i]];
            self.project.options.obfuscationPasses = ps;
            self.project.options.obfuscation = SPObfuscationCustom;
            self.project.options.useOLLVM = ps.count > 0;
            [self persist];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pickPasses];
            });
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openFile:(NSString *)path {
    if (!path.length) return;
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:e animated:YES];
}

- (void)copyBuildCommand {
    NSString *script = [SPBuilder scriptForProject:self.project options:self.project.options
                                           profile:self.profile ?: [[SPToolchain shared] ciProfileWithSDK:nil]
                                        backupPath:nil];
    UIPasteboard.generalPasteboard.string = script;
    [SPMotion hapticSuccess];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已复制编译脚本"
        message:@"可以粘贴到终端，或提交到 CI 复现" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showHistory {
    NSMutableString *text = [NSMutableString string];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm";
    for (NSDictionary *r in [[SPStore shared] buildHistory]) {
        if (![r[@"project"] isEqual:self.project.path]) continue;
        NSInteger state = [r[@"state"] integerValue];
        NSString *mark = state == 2 ? @"✓" : (state == 1 ? @"▶" : (state == 4 ? @"⏹" : @"✗"));
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:[r[@"started"] doubleValue]];
        [text appendFormat:@"%@ %@\n%@\n\n", mark, [f stringFromDate:d], r[@"summary"]];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"构建历史"
        message:(text.length ? text : @"还没有构建记录") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
