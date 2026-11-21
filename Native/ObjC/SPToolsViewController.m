//
//  SPToolsViewController.m
//

#import "SPToolsViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPAnimationKit.h"
#import "SPToolchain.h"
#import "SPToolchainInstaller.h"
#import "SPToolchainViewController.h"
#import "SPReverseViewController.h"
#import "SPTrollViewController.h"
#import "SPMountsViewController.h"
#import "SPLogsViewController.h"
#import "SPCrashViewController.h"
#import "SPRemoteViewController.h"
#import "SPSignatureViewController.h"
#import "SPCrossBuildViewController.h"
#import "SPSelfTestViewController.h"
#import "SPStore.h"
#import "SPCompat.h"

@interface SPToolItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) UIColor *tint;
@property (nonatomic, copy) NSString *badge;
@property (nonatomic, strong) Class controllerClass;
@end
@implementation SPToolItem
@end

@interface SPToolsViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSArray<SPToolItem *> *> *groups;
@property (nonatomic, strong) NSArray<NSString *> *groupTitles;
@end

@implementation SPToolsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"工具";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 64;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"t"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self buildItems];
    [self installGlassHeader];
}

- (void)installGlassHeader {
    SPGlassHeaderView *header = [[SPGlassHeaderView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    [header configureWithSymbol:@"wrench.and.screwdriver.fill"
                          title:@"工具"
                       subtitle:@"编译链、逆向、注入、挂载与诊断"
                           tint:[SPTheme info]];
    CGSize sz = [header systemLayoutSizeFittingSize:CGSizeMake(320, UIViewNoIntrinsicMetric)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, 320, MAX(96, sz.height));
    self.table.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildItems];
    [self.table reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // 交错入场：可见 cell 依次滑入
    NSArray *cells = self.table.visibleCells;
    if (cells.count) [SPAnimationKit stagger:cells offset:14];
}

- (void)buildItems {
    SPToolchainScan *scan = [SPToolchain shared].scan;

    // 组 1：构建相关
    SPToolItem *tc = [SPToolItem new];
    tc.title = @"工具链";
    tc.detail = [scan summary];
    tc.symbol = @"hammer.fill";
    tc.tint = [SPTheme gold];
    tc.controllerClass = SPToolchainViewController.class;

    // 组 2：逆向 + 注入
    SPToolItem *rev = [SPToolItem new];
    rev.title = @"逆向分析";
    rev.detail = [scan has:SPToolchainComponentReverse] ? @"radare2 / mt-macho / ldid" : @"逆向工具未安装";
    rev.symbol = @"binoculars.fill";
    rev.tint = [SPTheme gold];
    rev.controllerClass = SPReverseViewController.class;

    SPToolItem *inj = [SPToolItem new];
    inj.title = @"巨魔注入器";
    inj.detail = @"给任意 App 注入 dylib（自动备份）";
    inj.symbol = @"syringe.fill";
    inj.tint = [SPTheme warn];
    inj.controllerClass = SPTrollViewController.class;

    // 组 3：文件相关
    SPToolItem *mount = [SPToolItem new];
    mount.title = @"外部文件夹";
    mount.detail = @"WebDAV 挂载为本地目录";
    mount.symbol = @"externaldrive.connected.to.line.below";
    mount.tint = [SPTheme success];
    mount.controllerClass = SPMountsViewController.class;

    SPToolItem *crash = [SPToolItem new];
    crash.title = @"崩溃分析";
    crash.detail = @"解析 .ips / .crash，给结论与栈";
    crash.symbol = @"xmark.octagon.fill";
    crash.tint = [SPTheme danger];
    crash.controllerClass = SPCrashViewController.class;

    SPToolItem *audit = [SPToolItem new];
    audit.title = @"签名审计";
    audit.detail = @"查 ipa 装不上的原因（缺签名/截断/空壳 bundle）";
    audit.symbol = @"checkmark.shield.fill";
    audit.tint = [SPTheme success];
    audit.controllerClass = SPSignatureViewController.class;

    SPToolItem *selftest = [SPToolItem new];
    selftest.title = @"测试构建";
    selftest.detail = @"自动生成最小 tweak 并编译，逐步报告哪一环不通";
    selftest.symbol = @"checklist";
    selftest.tint = [SPTheme gold];
    selftest.controllerClass = SPSelfTestViewController.class;

    SPToolItem *cross = [SPToolItem new];
    cross.title = @"快速编译";
    cross.detail = @"不依赖 Theos：单文件直出已签名 dylib";
    cross.symbol = @"bolt.horizontal.circle.fill";
    cross.tint = [SPTheme gold];
    cross.controllerClass = SPCrossBuildViewController.class;

    SPToolItem *remote = [SPToolItem new];
    remote.title = @"局域网工作台";
    remote.detail = @"手机当服务器，电脑浏览器编辑与构建";
    remote.symbol = @"laptopcomputer.and.iphone";
    remote.tint = [SPTheme info];
    remote.controllerClass = SPRemoteViewController.class;

    SPToolItem *logs = [SPToolItem new];
    logs.title = @"日志";
    logs.detail = @"构建 / 注入 / 自检记录";
    logs.symbol = @"doc.text.magnifyingglass";
    logs.tint = [SPTheme gold];
    logs.controllerClass = SPLogsViewController.class;

    self.groupTitles = @[@"编译", @"分析与注入", @"文件与记录", @"远程与诊断"];
    self.groups = @[@[tc], @[selftest, cross], @[rev, inj, mount, logs], @[remote, crash, audit]];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)self.groups.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return self.groupTitles[s]; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        SPToolchainInstaller *inst = [SPToolchainInstaller shared];
        if (!inst.hasBundledToolchain) return @"这个包没有内置工具链，可在工具链页从文件导入。";
        if (!inst.isInstalled) return @"内置工具链尚未展开，进入「工具链」点展开即可（约一分钟）。";
        return @"内置工具链已就绪；SDK 需在工具链页导入。";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)self.groups[s].count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"t"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"t"];
    [SPTheme styleCell:cell];

    SPToolItem *item = self.groups[ip.section][ip.row];
    cell.textLabel.text = item.title;
    cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightMedium];
    cell.detailTextLabel.text = item.detail;
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // Swiftgram 风格：彩色圆角图标块
    cell.imageView.image = [self iconTile:item.symbol tint:item.tint];
    return cell;
}

/// 生成 29x29 的圆角彩色图标块（比纯 tint 的 symbol 更有层次）
- (UIImage *)iconTile:(NSString *)symbol tint:(UIColor *)tint {
    CGSize size = CGSizeMake(29, 29);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                            cornerRadius:7];
        [tint colorWithAlphaComponent:0.16].setFill;
        [path fill];
        UIImage *sym = [UIImage systemImageNamed:symbol
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                               weight:UIImageSymbolWeightSemibold]];
        UIImage *tinted = [sym imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize s = tinted.size;
        [tinted drawInRect:CGRectMake((size.width - s.width) / 2, (size.height - s.height) / 2, s.width, s.height)];
    }];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPToolItem *item = self.groups[ip.section][ip.row];
    UIViewController *vc = nil;
    if (item.controllerClass == SPReverseViewController.class) {
        vc = [[SPReverseViewController alloc] initWithBinaryPath:nil profile:nil];
    } else if (item.controllerClass) {
        vc = [[item.controllerClass alloc] init];
    }
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

@end
