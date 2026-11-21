//
//  SPSettingsViewController.m
//

#import "SPSettingsViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPStore.h"
#import "SPOutputNaming.h"
#import "SPModels.h"
#import "SPToolchain.h"
#import "SPToolchainInstaller.h"
#import "SPAnimationKit.h"
#import "SPToolchainDownloader.h"
#import "SPCompat.h"
#import "SPSession.h"
#import "SPJIT.h"
#import "SPBackground.h"
#import "SPPrivileged.h"
#import "SPTrollStoreFix.h"
#import "SPFileBrowserViewController.h"
#import "SPMountsViewController.h"
#import "SPMount.h"

typedef NS_ENUM(NSInteger, SPSection) {
    SPSectionBuildDefaults = 0,
    SPSectionObfuscation,
    SPSectionToolchain,
    SPSectionFiles,
    SPSectionMCP,
    SPSectionTarget,
    SPSectionDisplay,
    SPSectionAbout,
    SPSectionCount,
};

@interface SPSettingsViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) SPBuildOptions *draft;     // 默认选项草稿
@property (nonatomic, strong) UIProgressView *installProgress;
@property (nonatomic, copy) NSString *installStatus;
@property (nonatomic, assign) CGFloat logFontSize;
@end

@implementation SPSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    // 草稿：读取「默认选项」，改动即时落盘
    self.draft = [[SPStore shared] optionsForProjectPath:@"__defaults__"];
    self.logFontSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"Spark.logFontSize"];
    if (self.logFontSize <= 0) self.logFontSize = 12;

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"gearshape.fill", @"设置", @"编译默认值、工具链与环境", [SPTheme accent], 320);

    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)reload { [self.table reloadData]; }

#pragma mark - Table 骨架

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SPSectionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SPSectionBuildDefaults: return @"编译默认值（新建项目生效）";
        case SPSectionObfuscation:   return @"混淆（OLLVM）";
        case SPSectionToolchain:     return @"工具链";
        case SPSectionFiles:         return @"文件与缓存";
        case SPSectionMCP:           return @"MCP 服务（外部程序调用）";
        case SPSectionTarget:        return @"构建目标";
        case SPSectionDisplay:       return @"显示与反馈";
        default:                     return @"关于";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case SPSectionBuildDefaults:
            return @"这些是「新建项目」时的初始值；已有项目请在项目页单独调整。";
        case SPSectionObfuscation: {
            NSArray *p = self.draft.obfuscationPasses;
            return p.count
                ? [NSString stringWithFormat:@"当前：%@\n轻度=indbr+cse；均衡=+icall；强力=全部 5 个。混淆会明显变慢，且个别源码可能触发编译器崩溃，出问题先关掉。",
                   [p componentsJoinedByString:@" + "]]
                : @"未启用混淆。OLLVM 会显著拖慢编译（约 2~5 倍），release 前再开。";
        }
        case SPSectionToolchain: {
            SPToolchainInstaller *i = [SPToolchainInstaller shared];
            if (!i.hasBundledToolchain) return @"这个安装包里没有内置工具链。可以从「从文件导入工具链」补装。";
            if (!i.isInstalled) return @"内置工具链尚未展开，点上面「展开工具链」开始（Theos + 最小编译链，几秒）。";
            return [NSString stringWithFormat:
                    @"已安装到 %@\n\nTheos 与最小编译链随包内置；OLLVM / 逆向工具 / 完整工具集\n按需点下方下载。SDK 需自行导入。",
                    [i.installRoot stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]];
        }
        case SPSectionFiles:
            return @"「接收文件」会把文件复制到 App 自己的目录，之后在项目里可以直接引用。";
        case SPSectionMCP: {
            return @"MCP 让 Claude Desktop / Cursor 这类客户端直接调用 Spark 的编译与注入能力。\n"
                    "地址固定 127.0.0.1（只接受本机连接）；远程用请走 SSH 隧道。";
        }
        case SPSectionDisplay:
            return @"关闭「减弱动态效果」后才会播放 Gasp 动画。";
        default:
            return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SPSectionBuildDefaults: return 9;
        case SPSectionObfuscation:   return 4;
        // 运行时已全部内嵌进 ipa，不再有「按需下载」的组件行
        case SPSectionToolchain:     return 7;
        case SPSectionFiles:         return 5;
        case SPSectionMCP:           return 4;
        case SPSectionTarget:        return 4;
        // 显示区只有 4 项（触感/常亮/日志行数/字号）。
        // 之前这里写 7，而 cellForRow 的数组只有 4 项 —— 多出的
        // 第 5~7 行一渲染就抛 NSRangeException 崩溃。
        case SPSectionDisplay:       return 4;
        default:                     return 3;
    }
}

- (void)styleCell:(UITableViewCell *)cell {
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
    [self styleCell:cell];
    SPBuildOptions *o = self.draft;

    switch (ip.section) {
        case SPSectionBuildDefaults:
            [self configureBuildCell:cell row:ip.row options:o];
            break;

        case SPSectionObfuscation:
            switch (ip.row) {
                case 0:
                    cell.textLabel.text = @"启用 OLLVM";
                    [self addSwitch:cell on:o.useOLLVM tag:6000];
                    break;
                case 1:
                    cell.textLabel.text = @"混淆强度";
                    cell.detailTextLabel.text = SPAtIndex(@[@"无", @"轻度", @"均衡", @"强力", @"自定义"], o.obfuscation, @"");
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2:
                    cell.textLabel.text = @"Pass 多选";
                    cell.detailTextLabel.text = o.obfuscationPasses.count
                        ? [o.obfuscationPasses componentsJoinedByString:@" + "] : @"—";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                default:
                    cell.textLabel.text = @"一键套用推荐值";
                    cell.textLabel.textColor = [SPTheme accent];
                    break;
            }
            break;

        case SPSectionToolchain:
            [self configureToolchainCell:cell row:ip.row];
            break;

        case SPSectionFiles:
            [self configureFilesCell:cell row:ip.row];
            break;

        case SPSectionMCP: {
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            BOOL on = [d boolForKey:@"Spark.mcpEnabled"];
            NSInteger port = [d integerForKey:@"Spark.mcpPort"];
            if (port <= 0) port = 7878;
            switch (ip.row) {
                case 0:
                    cell.textLabel.text = @"启用 MCP 服务";
                    [self addSwitch:cell on:on tag:6200];
                    break;
                case 1:
                    cell.textLabel.text = @"监听端口";
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld（仅 127.0.0.1）", (long)port];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2:
                    cell.textLabel.text = @"服务状态";
                    cell.detailTextLabel.text = on ? @"运行中" : @"已停止";
                    cell.detailTextLabel.textColor = on ? [SPTheme success] : [SPTheme textDim];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    break;
                default:
                    cell.textLabel.text = @"复制客户端配置";
                    cell.textLabel.textColor = [SPTheme accent];
                    break;
            }
            break;
        }

        case SPSectionTarget: {
            NSArray *titles = @[@"默认构建目标", @"远程主机", @"GitHub 仓库", @"GitHub 分支"];
            cell.textLabel.text = SPAtIndex(titles, ip.row, @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            SPSettings *s = SPSettings.shared;
            switch (ip.row) {
                case 0: cell.detailTextLabel.text = SPAtIndex(@[@"本机", @"远程 SSH", @"GitHub CI"], s.defaultTarget, @""); break;
                case 1: cell.detailTextLabel.text = s.sshHost.length
                    ? [NSString stringWithFormat:@"%@@%@:%ld", s.sshUser, s.sshHost, (long)s.sshPort] : @"未配置"; break;
                case 2: cell.detailTextLabel.text = s.githubRepo.length ? s.githubRepo : @"未配置"; break;
                default: cell.detailTextLabel.text = s.githubBranch ?: @"main"; break;
            }
            break;
        }

        case SPSectionDisplay: {
            NSArray *titles = @[@"操作触感反馈", @"编译时屏幕常亮", @"日志最多行数", @"日志字号"];
            // 用 SPAtIndex：numberOfRowsInSection 声明了 7 行，
            // 而这里只有 4 项 —— ip.row 到 4/5/6 时 titles[ip.row]
            // 会抛 NSRangeException 并 abort。
            // 你的崩溃栈正是 cellForRowAtIndexPath → NSConstantArray → 异常退出。
            cell.textLabel.text = SPAtIndex(titles, ip.row, @"");
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            switch (ip.row) {
                case 0: [self addSwitch:cell on:[d boolForKey:@"Spark.haptics"] tag:6001]; break;
                case 1: [self addSwitch:cell on:SPSettings.shared.keepScreenOn tag:6002]; break;
                case 2:
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)SPSettings.shared.maxLogLines];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 3:
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", self.logFontSize];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 4: {
                    // 后台保活
                    cell.textLabel.text = @"后台保活（编译中）";
                    cell.detailTextLabel.text = [SPBackground shared].statusText;
                    UISwitch *sw = [[UISwitch alloc] init];
                    sw.tag = 6004;
                    sw.on = [SPBackground shared].userEnabled;
                    [sw addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = sw;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    break;
                }
                case 5: {
                    cell.textLabel.text = @"构建失败时提示自动修复";
                    cell.detailTextLabel.text = @"会改源码（有备份）";
                    UISwitch *sw = [[UISwitch alloc] init];
                    sw.tag = 6005;
                    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"Spark.autofixEnabled"];
                    [sw addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = sw;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    break;
                }
                default: {
                    // JIT 加速：只读状态 + 开关
                    cell.textLabel.text = @"JIT 加速";
                    cell.detailTextLabel.text = [SPJIT shared].statusText;
                    cell.detailTextLabel.font = [SPTheme caption];
                    UISwitch *sw = [[UISwitch alloc] init];
                    sw.tag = 6003;
                    sw.on = [SPJIT shared].userEnabled;
                    [sw addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = sw;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    break;
                }
            }
            break;
        }

        default: {
            NSArray *titles = @[@"版本与构建信息", @"运行环境自检", @"打开数据目录"];
            cell.textLabel.text = SPAtIndex(titles, ip.row, @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if (ip.row == 0) cell.detailTextLabel.text = SPVersion.shared.semver;
            break;
        }
    }
    return cell;
}

#pragma mark - 各分组配置

- (void)configureBuildCell:(UITableViewCell *)cell row:(NSInteger)row options:(SPBuildOptions *)o {
    switch (row) {
        case 0:
            cell.textLabel.text = @"架构";
            cell.detailTextLabel.text = SPAtIndex(@[@"arm64", @"arm64e", @"arm64 + arm64e"], o.arch, @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case 1:
            cell.textLabel.text = @"包格式";
            cell.detailTextLabel.text = SPAtIndex(@[@"deb（有根）", @"deb（无根 rootless）", @"deb（隐根 roothide）", @".app", @".tipa"], o.format, @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case 2:
            cell.textLabel.text = @"优化等级";
            cell.detailTextLabel.text = [o optimizationName];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case 3:
            cell.textLabel.text = @"默认 Debug 编译";
            [self addSwitch:cell on:o.debug tag:6100];
            break;
        case 4:
            cell.textLabel.text = @"并行编译";
            cell.detailTextLabel.text = o.parallel ? [NSString stringWithFormat:@"-j%ld", (long)o.jobs] : @"串行";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case 5:
            cell.textLabel.text = @"构建前清理";
            [self addSwitch:cell on:o.cleanBeforeBuild tag:6101];
            break;
        case 7:
            cell.textLabel.text = @"产物命名模板";
            cell.detailTextLabel.text = SPSettings.shared.outputPattern.length
                ? SPSettings.shared.outputPattern : @"Theos 默认";
            cell.detailTextLabel.font = [SPTheme mono:11];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case 6:
            cell.textLabel.text = @"ldid 补签";
            [self addSwitch:cell on:o.signWithLdid tag:6102];
            break;
        default:
            cell.textLabel.text = @"撤销符号表（strip）";
            [self addSwitch:cell on:o.strip tag:6103];
            break;
    }
}

- (void)configureToolchainCell:(UITableViewCell *)cell row:(NSInteger)row {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    switch (row) {
        case 0: {
            cell.textLabel.text = @"内置工具链";
            if (!inst.hasBundledToolchain) cell.detailTextLabel.text = @"未内置";
            else if (inst.isInstalling) cell.detailTextLabel.text = @"展开中…";
            else if (inst.isInstalled) cell.detailTextLabel.text = @"已就绪";
            else cell.detailTextLabel.text = @"未展开";
            cell.detailTextLabel.textColor = inst.isInstalled ? [SPTheme success] : [SPTheme warn];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case 1: {
            cell.textLabel.text = inst.isInstalled ? @"重新展开工具链" : @"展开工具链";
            cell.textLabel.textColor = [SPTheme accent];
            cell.selectionStyle = inst.isInstalled || inst.hasBundledToolchain
                ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
            break;
        }
        case 2: {
            NSArray *sdks = [[SPToolchain shared] availableSDKs];
            cell.textLabel.text = @"iPhoneOS SDK";
            cell.detailTextLabel.text = sdks.count ? sdks.lastObject : @"未导入";
            cell.detailTextLabel.textColor = sdks.count ? [SPTheme textDim] : [SPTheme danger];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 3:
            cell.textLabel.text = @"导入 SDK 压缩包…";
            cell.textLabel.textColor = [SPTheme accent];
            break;
        case 4: {
            cell.textLabel.text = @"重新扫描工具链";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case 5: {
            cell.textLabel.text = @"工具链详情";
            cell.detailTextLabel.text = [[SPToolchain shared].scan summary];
            cell.detailTextLabel.numberOfLines = 2;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 6: {
            // 运行身份 + 自修入口：非 root 时给出可操作的修复引导
            cell.textLabel.text = @"运行身份";
            cell.detailTextLabel.text = [SPTrollStoreFix statusText];
            cell.detailTextLabel.font = [SPTheme caption];
            cell.detailTextLabel.numberOfLines = 2;
            cell.detailTextLabel.textColor = ([SPTrollStoreFix state] == SPTrollStoreStateOK)
                ? [SPTheme success] : [SPTheme danger];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        default: {
            NSArray<SPComponentInfo *> *comps = [[SPToolchainDownloader shared] components];
            NSInteger idx = row - 7;
            if (idx < 0 || idx >= (NSInteger)comps.count) {
                cell.textLabel.text = @"";
                break;
            }
            SPComponentInfo *c = comps[idx];
            cell.textLabel.text = c.title;
            cell.textLabel.textColor = [SPTheme text];
            cell.imageView.image = [UIImage systemImageNamed:c.symbol];
            cell.imageView.tintColor = c.isInstalled ? [SPTheme success] : [SPTheme textDim];
            cell.detailTextLabel.text = c.isInstalled
                ? @"已下载"
                : [NSString stringWithFormat:@"%@ · 约 %@", c.detail, [SPUtil formatBytes:c.approxSize]];
            cell.detailTextLabel.textColor = c.isInstalled ? [SPTheme success] : [SPTheme textDim];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
    }
}

- (void)configureFilesCell:(UITableViewCell *)cell row:(NSInteger)row {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *inbox = [[SPStore shared] inboxDirectory];
    switch (row) {
        case 0:
            cell.textLabel.text = @"接收文件…";
            cell.textLabel.textColor = [SPTheme accent];
            cell.detailTextLabel.text = @"dylib / deb / zip / ipa";
            break;
        case 1: {
            NSUInteger count = [fm contentsOfDirectoryAtPath:inbox error:NULL].count;
            cell.textLabel.text = @"打开收件箱";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 个文件", (unsigned long)count];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 2: {
            unsigned long long total = [self directorySize:[[SPStore shared] artifactsDirectory]];
            total += [self directorySize:[[SPStore shared] logsDirectory]];
            cell.textLabel.text = @"清除缓存（日志/产物）";
            cell.textLabel.textColor = [SPTheme danger];
            cell.detailTextLabel.text = [SPUtil formatBytes:total];
            break;
        }
        case 3: {
            unsigned long long total = [self directorySize:[SPToolchainInstaller shared].installRoot];
            cell.textLabel.text = @"工具链占用";
            cell.detailTextLabel.text = [SPUtil formatBytes:total];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        default: {
            NSUInteger n = [[SPMountManager shared] mounts].count;
            cell.textLabel.text = @"外部文件夹（WebDAV / SMB）";
            cell.detailTextLabel.text = n ? [NSString stringWithFormat:@"%lu 个挂载", (unsigned long)n] : @"未挂载";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
    }
}

- (unsigned long long)directorySize:(NSString *)dir {
    NSFileManager *fm = NSFileManager.defaultManager;
    unsigned long long total = 0;
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:dir];
    NSString *rel;
    while ((rel = [e nextObject])) {
        NSDictionary *a = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:rel] error:NULL];
        total += a.fileSize;
    }
    return total;
}

- (void)addSwitch:(UITableViewCell *)cell on:(BOOL)on tag:(NSInteger)tag {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

#pragma mark - 交互

- (void)switchChanged:(UISwitch *)sw {
    SPBuildOptions *o = self.draft;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch (sw.tag) {
        case 6000:
            o.useOLLVM = sw.isOn;
            if (!sw.isOn) o.obfuscation = SPObfuscationNone;
            else if (o.obfuscation == SPObfuscationNone) o.obfuscation = SPObfuscationLight;
            break;
        case 6001: [d setBool:sw.isOn forKey:@"Spark.haptics"]; [SPMotion hapticLight]; break;
        case 6002: SPSettings.shared.keepScreenOn = sw.isOn; [SPSettings.shared save]; break;
        case 6005:
            [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"Spark.autofixEnabled"];
            [self toast:sw.isOn ? @"已开启（失败时会提示改源码）" : @"已关闭自动修复"];
            return;
        case 6004:
            [SPBackground shared].userEnabled = sw.isOn;
            [self.table reloadData];
            [self toast:sw.isOn ? @"后台保活已开启" : @"后台保活已关闭"];
            return;
        case 6003:
            [SPJIT shared].userEnabled = sw.isOn;
            if (sw.isOn) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [[SPJIT shared] probe]; });
            [self.table reloadData];
            [self toast:sw.isOn ? @"已开启 JIT 加速" : @"已关闭 JIT 加速"];
            return;
        case 6200:
            [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"Spark.mcpEnabled"];
            [self.table reloadData];
            [self toast:sw.isOn ? @"MCP 服务已启用" : @"MCP 服务已停止"];
            return;
        case 6100: o.debug = sw.isOn; break;
        case 6101: o.cleanBeforeBuild = sw.isOn; break;
        case 6102: o.signWithLdid = sw.isOn; break;
        case 6103: o.strip = sw.isOn; break;
    }
    [self persistDefaults];
}

- (void)editOutputPattern {
    NSString *cur = SPSettings.shared.outputPattern ?: @"";
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"产物命名模板"
        message:[NSString stringWithFormat:@"可用占位符：\n%@\n\n留空则用 Theos 默认命名。",
                 [[SPOutputNaming availablePlaceholders] componentsJoinedByString:@"  "]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.placeholder = @"{name}_{version}_{packageArch}";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.font = [SPTheme mono:13];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *val = a.textFields.firstObject.text ?: @"";
        val = [val stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (val.length) {
            NSString *err = [SPOutputNaming validatePattern:val];
            if (err) {
                [self alert:@"模板有问题" message:err];
                return;
            }
        }
        SPSettings.shared.outputPattern = val.length ? val : nil;
        [SPSettings.shared save];
        [self.table reloadData];
        [self toast:val.length ? @"已保存命名模板" : @"已恢复默认命名"];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)persistDefaults {
    [[SPStore shared] saveOptions:self.draft forProjectPath:@"__defaults__"];
    [self.table reloadData];
    [SPMotion hapticLight];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPBuildOptions *o = self.draft;

    if (ip.section == SPSectionBuildDefaults) {
        switch (ip.row) {
            case 0: {
                [self pick:@[@"arm64", @"arm64e", @"arm64 + arm64e"] title:@"默认架构" apply:^(NSInteger i) { o.arch = i; }];
                break;
            }
            case 1: {
                [self pick:@[@"deb（有根）", @"deb（无根 rootless）", @"deb（隐根 roothide）", @".app", @".tipa"] title:@"默认包格式" apply:^(NSInteger i) { o.format = i; }];
                break;
            }
            case 2: {
                [self pick:@[@"-O0（调试，最快编译）", @"-Og（调试友好优化）", @"-O1（轻度）",
                             @"-O2（发布推荐）", @"-O3（激进）", @"-Os（优化体积）",
                             @"-Oz（极限体积）", @"-Ofast（数学优化，慎用）"] title:@"优化等级" apply:^(NSInteger i) {
                    o.optimization = (SPOptimization)i;
                }];
                break;
            }
            case 4: {
                [self pick:@[@"串行", @"并行 -j2", @"并行 -j4", @"并行 -j6", @"并行 -j8"] title:@"并行度" apply:^(NSInteger i) {
                    o.parallel = i > 0;
                    o.jobs = i == 0 ? 1 : i * 2;
                }];
                break;
            }
            default: break;
        }
        return;
    }

    if (ip.section == SPSectionObfuscation) {
        if (ip.row == 1) {
            [self pick:@[@"无", @"轻度（indbr + cse）", @"均衡（indbr + icall + cse）",
                         @"强力（全部 5 个）", @"自定义"] title:@"混淆强度" apply:^(NSInteger i) {
                o.obfuscation = i;
                o.useOLLVM = i != SPObfuscationNone;
            }];
        } else if (ip.row == 2) {
            [self pickPasses];
        } else if (ip.row == 3) {
            o.obfuscation = SPObfuscationBalanced;
            o.useOLLVM = YES;
            [self persistDefaults];
            [self toast:@"已套用「均衡」：indbr + icall + cse"];
        }
        return;
    }

    if (ip.section == SPSectionToolchain) {
        switch (ip.row) {
            case 1: [self installToolchain]; break;
            case 2: [self showToolchainDetail]; break;
            case 3: [self importSDK]; break;
            case 4: [[SPToolchain shared] rescan]; [self.table reloadData]; [self toast:@"已重新扫描"]; break;
            case 5: [self showToolchainDetail]; break;
            case 6: {
                // 自修入口：直接给出诊断与修复方式，不只是显示状态
                [SPTrollStoreFix presentGuideFrom:self];
                break;
            }
            default: {
                // 运行时已全部内嵌，这里不再有可下载组件
                NSArray<SPComponentInfo *> *comps = @[];
                NSInteger idx = ip.row - 7;
                if (idx >= 0 && idx < (NSInteger)comps.count) {
                    SPComponentInfo *c = comps[idx];
                    if (c.isInstalled) {
                        UIAlertController *a = [UIAlertController alertControllerWithTitle:c.title
                            message:@"该组件已下载，要删除释放空间吗？" preferredStyle:UIAlertControllerStyleActionSheet];
                        [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                            [[SPToolchainDownloader shared] remove:c.component];
                            [self.table reloadData];
                        }]];
                        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                        a.popoverPresentationController.sourceView = self.view;
                        [self presentViewController:a animated:YES completion:nil];
                    } else {
                        [self downloadComponent:c];
                    }
                }
                break;
            }
        }
        return;
    }

    if (ip.section == SPSectionFiles) {
        switch (ip.row) {
            case 0: [self receiveFiles]; break;
            case 1: {
                SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
                    initWithRootPath:[[SPStore shared] inboxDirectory] pickMode:NO fileFilters:nil onPick:nil];
                [self.navigationController pushViewController:b animated:YES];
                break;
            }
            case 2: [self clearCache]; break;
            case 3: break;   // 只读占位
            default: {
                SPMountsViewController *vc = [[SPMountsViewController alloc] init];
                [self.navigationController pushViewController:vc animated:YES];
                break;
            }
        }
        return;
    }

    if (ip.section == SPSectionMCP) {
        if (ip.row == 1) {
            NSArray *ports = @[@"7878", @"8787", @"17878"];
            [self pick:ports title:@"MCP 监听端口" apply:^(NSInteger i) {
                [[NSUserDefaults standardUserDefaults] setInteger:[ports[i] integerValue] forKey:@"Spark.mcpPort"];
                [self.table reloadData];
            }];
        } else if (ip.row == 3) {
            NSInteger port = [[NSUserDefaults standardUserDefaults] integerForKey:@"Spark.mcpPort"];
            if (!port) port = 7878;
            NSString *json = [NSString stringWithFormat:
                @"{\n  \"mcpServers\": {\n    \"spark\": {\n"
                 "      \"url\": \"http://127.0.0.1:%ld/mcp\"\n"
                 "    }\n  }\n}", (long)port];
            UIPasteboard.generalPasteboard.string = json;
            [SPMotion hapticSuccess];
            [self toast:@"客户端配置已复制"];
        }
        return;
    }
    if (ip.section == SPSectionTarget) { [self editTargetAt:ip.row]; return; }

    if (ip.section == SPSectionBuildDefaults && ip.row == 7) {
        [self editOutputPattern];
        return;
    }

    if (ip.section == SPSectionDisplay) {
        if (ip.row == 2) {
            [self pick:@[@"2000", @"5000", @"10000", @"20000"] title:@"日志最多行数" apply:^(NSInteger i) {
                NSArray<NSNumber *> *lineOptions = @[ @2000, @5000, @10000, @20000 ];
                SPSettings.shared.maxLogLines = lineOptions[i].integerValue;
                [SPSettings.shared save];
                [self persistDefaults];
            }];
        } else if (ip.row == 3) {
            [self pick:@[@"10 pt", @"11 pt", @"12 pt", @"14 pt", @"16 pt"] title:@"日志字号" apply:^(NSInteger i) {
                NSArray<NSNumber *> *fontOptions = @[ @10, @11, @12, @14, @16 ];
                self.logFontSize = (CGFloat)fontOptions[i].doubleValue;
                [[NSUserDefaults standardUserDefaults] setFloat:self.logFontSize forKey:@"Spark.logFontSize"];
                [self.table reloadData];
            }];
        }
        return;
    }

    // 关于
    if (ip.row == 0) [self showAbout];
    else if (ip.row == 1) [self runSelfCheck];
    else {
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
            initWithRootPath:NSHomeDirectory() pickMode:NO fileFilters:nil onPick:nil];
        [self.navigationController pushViewController:b animated:YES];
    }
}

#pragma mark - 选择器

- (void)pick:(NSArray<NSString *> *)titles title:(NSString *)title apply:(void (^)(NSInteger))apply {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            apply(i);
            [self persistDefaults];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 120, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickPasses {
    NSArray *names = @[@"indbr（间接跳转）", @"icall（间接调用）", @"indgv（间接全局）",
                       @"cse（字符串加密）", @"cff（控制流平坦化）"];
    NSArray *ids = @[@"indbr", @"icall", @"indgv", @"cse", @"cff"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"选择 OLLVM Pass"
        message:@"可多选，选完点「完成」" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < (NSInteger)ids.count; i++) {
        BOOL on = [self.draft.obfuscationPasses containsObject:ids[i]];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", on ? @"✓" : @"○", names[i]]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSMutableArray *ps = [self.draft.obfuscationPasses mutableCopy] ?: [NSMutableArray array];
            if (on) [ps removeObject:ids[i]]; else [ps addObject:ids[i]];
            self.draft.obfuscationPasses = ps;
            self.draft.obfuscation = SPObfuscationCustom;
            self.draft.useOLLVM = ps.count > 0;
            [self persistDefaults];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pickPasses];
            });
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 工具链

- (void)installToolchain {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    if (!inst.hasBundledToolchain) {
        [self alert:@"没有内置工具链" message:@"这个安装包里没带 Toolchain，可用「从文件导入工具链」补装。"];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"展开工具链"
        message:@"会把包内的编译工具（约 480MB）展开到 App 的数据目录。这需要几十秒，期间请留在本页。"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self runInstall:NO];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runInstall:(BOOL)force {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    self.installStatus = @"准备中…";
    self.installProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.installProgress.progressTintColor = [SPTheme accent];
    self.installProgress.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat w = self.view.bounds.size.width - 120;
    CGRect f = CGRectMake((self.view.bounds.size.width - w) / 2, self.view.bounds.size.height / 2 - 8, w, 4);
    self.installProgress.frame = f;
    [self.view addSubview:self.installProgress];

    UILabel *label = [[UILabel alloc] init];
    label.tag = 9001;
    label.text = self.installStatus;
    label.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightMedium];
    label.textColor = [SPTheme text];
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(20, CGRectGetMinY(f) - 28, self.view.bounds.size.width - 40, 20);
    [self.view addSubview:label];

    void (^done)(BOOL, NSError *) = ^(BOOL ok, NSError *err) {
        [self.installProgress removeFromSuperview];
        [[self.view viewWithTag:9001] removeFromSuperview];
        self.installProgress = nil;
        [self.table reloadData];
        if (ok) {
            [SPMotion hapticSuccess];
            [self toast:@"工具链已就绪"];
            [[SPToolchain shared] rescan];
        } else {
            [SPMotion hapticError];
            [self alert:@"展开失败" message:err.localizedDescription ?: @"未知错误"];
        }
    };

    SPInstallProgress prog = ^(CGFloat frac, NSString *status) {
        self.installProgress.progress = frac;
        [(UILabel *)[self.view viewWithTag:9001] setText:status];
    };

    [self.table reloadData];
    if (force) [inst reinstallWithProgress:prog completion:done];
    else [inst installWithProgress:prog completion:done];
}

- (void)downloadComponent:(SPComponentInfo *)c {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:c.title
        message:[NSString stringWithFormat:@"%@\n\n下载约 %@，需要联网。", c.detail, [SPUtil formatBytes:c.approxSize]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        // 进度条（复用安装工具链那套 UI）
        self.installStatus = @"准备下载…";
        self.installProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        self.installProgress.progressTintColor = [SPTheme accent];
        CGFloat w = self.view.bounds.size.width - 120;
        CGRect f = CGRectMake((self.view.bounds.size.width - w) / 2, self.view.bounds.size.height / 2 - 8, w, 4);
        self.installProgress.frame = f;
        [self.view addSubview:self.installProgress];

        UILabel *label = [[UILabel alloc] init];
        label.tag = 9002;
        label.text = c.title;
        label.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightMedium];
        label.textColor = [SPTheme text];
        label.textAlignment = NSTextAlignmentCenter;
        label.frame = CGRectMake(20, CGRectGetMinY(f) - 28, self.view.bounds.size.width - 40, 20);
        [self.view addSubview:label];

        __weak typeof(self) weakSelf = self;
        [[SPToolchainDownloader shared] download:c.component progress:^(CGFloat frac, NSString *status) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            self.installProgress.progress = frac;
            [(UILabel *)[self.view viewWithTag:9002] setText:status];
        } completion:^(BOOL ok, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.installProgress removeFromSuperview];
            [[self.view viewWithTag:9002] removeFromSuperview];
            self.installProgress = nil;
            [self.table reloadData];
            if (ok) {
                [SPMotion hapticSuccess];
                [self toast:[NSString stringWithFormat:@"%@ 已就绪", c.title]];
            } else {
                [SPMotion hapticError];
                [self alert:@"下载失败" message:error.localizedDescription ?: @"未知错误"];
            }
        }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showToolchainDetail {
    SPToolchainScan *scan = [SPToolchain shared].scan;
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"%s\n\n", [scan summary].UTF8String];
    NSArray *names = @[@"Theos", @"SDK", @"Darwin 工具", @"OLLVM", @"逆向工具", @"Python", @"Node", @"SSH"];
    for (NSInteger i = 0; i < SPToolchainComponentCount; i++) {
        NSString *p = [scan pathFor:(SPToolchainComponent)i];
        [s appendFormat:@"%@ %@\n%@\n\n", [scan has:(SPToolchainComponent)i] ? @"✓" : @"✗",
                      i < (NSInteger)names.count ? names[i] : @"?", p.length ? p : @"（未找到）"];
    }
    NSArray *remedies = [scan remedies];
    if (remedies.count) [s appendFormat:@"建议：\n• %@", [remedies componentsJoinedByString:@"\n• "]];
    [self alert:@"工具链详情" message:s];
}

- (void)importSDK {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data", @"public.item", @"public.folder"]
                       inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self.navigationController presentViewController:p animated:YES completion:nil];
}

#pragma mark - 文件接收

- (void)receiveFiles {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data", @"public.item"]
                       inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    p.allowsMultipleSelection = YES;
    [self.navigationController presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *inbox = [[SPStore shared] inboxDirectory];
    [fm createDirectoryAtPath:inbox withIntermediateDirectories:YES attributes:nil error:NULL];

    NSInteger ok = 0;
    NSMutableString *detail = [NSMutableString string];
    for (NSURL *url in urls) {
        // SDK 目录：直接放到 SDKs 目录
        BOOL isDir = NO;
        NSString *src = url.path;
        [fm fileExistsAtPath:src isDirectory:&isDir];

        NSString *dest = nil;
        if (isDir && ([src.lastPathComponent hasSuffix:@".sdk"] || [src.lastPathComponent hasSuffix:@".xcarchive"])) {
            NSString *sdks = [[SPStore shared] sdksDirectory];
            [fm createDirectoryAtPath:sdks withIntermediateDirectories:YES attributes:nil error:NULL];
            dest = [sdks stringByAppendingPathComponent:src.lastPathComponent];
        } else if ([src.lastPathComponent hasSuffix:@".sdk"] ||
                   [src.lastPathComponent.lowercaseString hasSuffix:@"sdk.zip"] ||
                   [src.lastPathComponent.lowercaseString hasSuffix:@"sdks.zip"]) {
            dest = [[[SPStore shared] sdksDirectory] stringByAppendingPathComponent:src.lastPathComponent];
            [fm createDirectoryAtPath:[[SPStore shared] sdksDirectory] withIntermediateDirectories:YES attributes:nil error:NULL];
        } else {
            dest = [inbox stringByAppendingPathComponent:src.lastPathComponent];
        }

        [fm removeItemAtPath:dest error:NULL];
        NSError *err = nil;
        if ([fm copyItemAtPath:src toPath:dest error:&err]) {
            ok++;
            [detail appendFormat:@"✓ %@\n", dest.lastPathComponent];
            // SDK 压缩包自动解开
            if ([dest.lowercaseString hasSuffix:@".zip"] &&
                ([dest.lowercaseString containsString:@"sdk"])) {
                [self unzipSDK:dest];
            }
        } else {
            [detail appendFormat:@"✗ %@（%@）\n", src.lastPathComponent, err.localizedDescription ?: @"失败"];
        }
    }
    [[SPToolchain shared] rescan];
    [self.table reloadData];
    if (ok) [SPMotion hapticSuccess];
    [self alert:(ok ? @"已接收" : @"未接收") message:[NSString stringWithFormat:@"收到 %ld 个文件：\n%@", (long)ok, detail]];
}

/// 用内置的 unzip 解 SDK 压缩包
- (void)unzipSDK:(NSString *)zipPath {
    NSString *unzip = [SPUtil findExecutable:@[@"unzip"] searchDirs:@[
        [SPToolchainInstaller shared].binDir, @"/usr/bin", @"/var/jb/usr/bin"]];
    if (!unzip) return;
    NSString *dir = [[SPStore shared] sdksDirectory];
    SPSession *s = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:dir];
    [s runShell:[NSString stringWithFormat:@"%@ -oq %@ -d %@", [SPUtil shellQuote:unzip],
                 [SPUtil shellQuote:zipPath], [SPUtil shellQuote:dir]]];
}

- (void)clearCache {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清除缓存"
        message:@"会删除构建产物与日志（项目源码、工具链、收件箱不受影响）。"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSFileManager *fm = NSFileManager.defaultManager;
        for (NSString *d in @[[[SPStore shared] artifactsDirectory], [[SPStore shared] logsDirectory]]) {
            for (NSString *f in [fm contentsOfDirectoryAtPath:d error:NULL] ?: @[]) {
                [fm removeItemAtPath:[d stringByAppendingPathComponent:f] error:NULL];
            }
        }
        [self.table reloadData];
        [self toast:@"已清除"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 构建目标

- (void)editTargetAt:(NSInteger)row {
    SPSettings *s = SPSettings.shared;
    if (row == 0) {
        [self pick:@[@"本机（真机编译）", @"远程设备（SSH）", @"GitHub Actions"] title:@"默认构建目标" apply:^(NSInteger i) {
            s.defaultTarget = i;
            [s save];
        }];
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
            s.sshUser = user.length ? user : @"mobile";
            s.sshHost = colon.location == NSNotFound ? rest : [rest substringToIndex:colon.location];
            s.sshPort = colon.location == NSNotFound ? 22 : [[rest substringFromIndex:colon.location + 1] integerValue];
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

#pragma mark - 其它

- (void)showAbout {
    NSString *msg = [NSString stringWithFormat:
        @"Spark %@\n构建 %@\n%@\n\n"
         "参考 Rein 的可视化编译工具：\n"
         "• Theos / Logos 一键编译（内置交叉编译工具链）\n"
         "• OLLVM（Arkari LLVM 16）混淆，5 个 pass 可组合\n"
         "• 逆向工具台（radare2 / mt-macho / ldid）\n"
         "• 巨魔（TrollStore）注入器\n\n"
         "MIT License",
        SPVersion.shared.semver, SPVersion.shared.gitDescribe, SPVersion.shared.builtAt];
    [self alert:@"关于 Spark" message:msg];
}

- (void)runSelfCheck {
    NSMutableString *s = [NSMutableString string];
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    [s appendFormat:@"内置工具链：%@\n", inst.hasBundledToolchain ? @"有" : @"无"];
    [s appendFormat:@"已展开：%@\n", inst.isInstalled ? @"是" : @"否"];
    [s appendFormat:@"安装路径：%@\n\n", inst.installRoot];
    [s appendFormat:@"%@\n\n", [[SPToolchain shared].scan summary]];
    NSArray *r = [[SPToolchain shared].scan remedies];
    if (r.count) [s appendFormat:@"建议：%@", [r componentsJoinedByString:@"\n"]];
    [self alert:@"环境自检" message:s];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toast:(NSString *)text {
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
        [l.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-SPSpaceHuge],
        [l.heightAnchor constraintEqualToConstant:32],
        [l.widthAnchor constraintGreaterThanOrEqualToConstant:160],
    ]];
    [SPMotion appear:^{ l.alpha = 1; }];
    [SPMotion disappear:^{ l.alpha = 0; } completion:^{ [l removeFromSuperview]; }];
}

@end
