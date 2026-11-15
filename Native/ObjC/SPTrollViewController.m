//
//  SPTrollViewController.m
//  巨魔注入器 —— 交互与流程照搬 TrollFools：
//    顶部搜索 + 已安装 App 列表 → 点进注入面板（插件列表 + 选项 + 执行）
//

#import "SPTrollViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPStore.h"
#import "SPSession.h"
#import "SPCompat.h"
#import "SPFileBrowserViewController.h"
#import "SPEditorViewController.h"
#import "SPToolchain.h"
#import "SPToolchainInstaller.h"
#import "SPBackground.h"

static NSString *const kAppBundleRoot = @"/private/var/containers/Bundle/Application";

#pragma mark - 数据模型

@interface SPTrollApp : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, copy) NSString *executable;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) BOOL isSystem;
@property (nonatomic, copy, nullable) NSString *iconPath;
@end
@implementation SPTrollApp
@end

@interface SPTrollPlugin : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL enabled;
@end
@implementation SPTrollPlugin
@end

#pragma mark - App 列表（TrollFools 首页）

@interface SPTrollViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) NSArray<SPTrollApp *> *apps;
@end

@implementation SPTrollViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"注入";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 62;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"app"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // TrollFools：顶部搜索，默认收起
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索已安装的 App";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(reloadApps)];
    self.navigationItem.rightBarButtonItem = refresh;

    [self reloadApps];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadApps)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - 枚举（照 TrollFools 的 LSApplicationProxy 思路，这里走文件系统）

- (void)reloadApps {
    NSMutableArray *list = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;

    // 1) TrollStore 装的 App（容器目录，UUID 下一层是 Xxx.app）
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:kAppBundleRoot error:NULL] ?: @[]) {
        NSString *dir = [kAppBundleRoot stringByAppendingPathComponent:uuid];
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
            if (![name hasSuffix:@".app"]) continue;
            SPTrollApp *a = [self appAtPath:[dir stringByAppendingPathComponent:name] system:NO];
            if (a) [list addObject:a];
        }
    }
    // 2) 系统 App（/Applications 下没有 UUID 的）
    for (NSString *name in [fm contentsOfDirectoryAtPath:@"/Applications" error:NULL] ?: @[]) {
        if (![name hasSuffix:@".app"]) continue;
        SPTrollApp *a = [self appAtPath:[@"/Applications" stringByAppendingPathComponent:name] system:YES];
        if (a && ![self containsBundleId:a.bundleId in:list]) [list addObject:a];
    }

    [list sortUsingComparator:^NSComparisonResult(SPTrollApp *a, SPTrollApp *b) {
        if ([a.bundleId isEqualToString:@"com.HuQing.Spark"]) return NSOrderedAscending;
        if ([b.bundleId isEqualToString:@"com.HuQing.Spark"]) return NSOrderedDescending;
        return [a.displayName localizedStandardCompare:b.displayName];
    }];
    self.apps = list;
    [self.table reloadData];
}

- (BOOL)containsBundleId:(NSString *)bid in:(NSArray<SPTrollApp *> *)list {
    for (SPTrollApp *a in list) if ([a.bundleId isEqualToString:bid]) return YES;
    return NO;
}

- (nullable SPTrollApp *)appAtPath:(NSString *)path system:(BOOL)system {
    NSString *plist = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
    if (!info) return nil;
    SPTrollApp *a = [SPTrollApp new];
    a.appPath = path;
    a.isSystem = system;
    a.bundleId = info[@"CFBundleIdentifier"] ?: @"";
    a.executable = info[@"CFBundleExecutable"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    a.version = info[@"CFBundleShortVersionString"] ?: @"";
    NSString *display = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
    a.displayName = display.length ? display : path.lastPathComponent.stringByDeletingPathExtension;
    // 图标
    NSArray *icons = info[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
    NSString *iconName = icons.lastObject ?: info[@"CFBundleIconFile"];
    if (iconName.length) {
        for (NSString *cand in @[iconName, [iconName stringByAppendingString:@"@2x"], [iconName stringByAppendingString:@"@3x"]]) {
            for (NSString *ext in @[@"@3x.png", @"@2x.png", @".png", @""]) {
                NSString *p = [path stringByAppendingPathComponent:[cand stringByAppendingString:ext]];
                if ([NSFileManager.defaultManager fileExistsAtPath:p]) { a.iconPath = p; break; }
            }
            if (a.iconPath) break;
        }
    }
    return a;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.filter = sc.searchBar.text ?: @"";
    [self.table reloadData];
}

- (NSArray<SPTrollApp *> *)visibleApps {
    if (!self.filter.length) return self.apps;
    NSMutableArray *out = [NSMutableArray array];
    for (SPTrollApp *a in self.apps) {
        if ([a.displayName localizedCaseInsensitiveContainsString:self.filter] ||
            [a.bundleId localizedCaseInsensitiveContainsString:self.filter]) [out addObject:a];
    }
    return out;
}

#pragma mark - 列表

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"已安装的 App（%lu）", (unsigned long)[self visibleApps].count];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (self.apps.count) return @"点任意 App 进入注入面板：加 dylib / framework / bundle，一键注入（自动备份）。";
    return @"没有枚举到 App。可能原因：\n• 缺少平台权限（重新用带 entitlements 的签名安装）\n• 不在越狱/TrollStore 环境";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [self visibleApps].count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    [SPTheme styleCell:cell];
    SPTrollApp *a = [self visibleApps][ip.row];

    cell.textLabel.text = a.displayName;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", a.bundleId,
                                 a.version.length ? [@"  ·  " stringByAppendingString:a.version] : @""];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // 图标：优先用 App 自己的，找不到用占位
    UIImage *icon = a.iconPath ? [UIImage imageWithContentsOfFile:a.iconPath] : nil;
    if (!icon) icon = [UIImage systemImageNamed:@"app"];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(30, 30)];
    UIImage *small = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 30, 30) cornerRadius:7] addClip];
        [icon drawInRect:CGRectMake(0, 0, 30, 30)];
    }];
    cell.imageView.image = small;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPTrollApp *a = [self visibleApps][ip.row];
    SPTrollInjectPanel *panel = [[SPTrollInjectPanel alloc] initWithApp:a];
    panel.onFinished = ^{ [self reloadApps]; };
    [self.navigationController pushViewController:panel animated:YES];
}

@end

#pragma mark - 注入面板（TrollFools 的 InjectView）

@interface SPTrollInjectPanel () <UIDocumentPickerDelegate>
@property (nonatomic, strong) SPTrollApp *app;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<SPTrollPlugin *> *plugins;
@property (nonatomic, assign) BOOL weakLoad;
@property (nonatomic, assign) BOOL coreTrust;
@property (nonatomic, assign) BOOL wantLdid;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SPTrollInjectPanel

- (instancetype)initWithApp:(SPTrollApp *)app {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _app = app;
        _plugins = [NSMutableArray array];
        _weakLoad = YES;
        _coreTrust = YES;
        _wantLdid = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = self.app.displayName;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIBarButtonItem *run = [[UIBarButtonItem alloc] initWithTitle:@"注入"
        style:UIBarButtonItemStyleDone target:self action:@selector(runInjection)];
    self.navigationItem.rightBarButtonItem = run;
}

#pragma mark 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"目标", @"插件", @"选项", @"操作"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) return @"支持 dylib / framework / bundle，也可直接选 .deb 或 .zip（自动解包）。";
    if (s == 3) return @"注入会修改 App 本体，第一步自动备份为 .sparkbak；出问题改名恢复即可。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return (NSInteger)self.plugins.count + 1;
    if (s == 2) return 3;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;

    if (ip.section == 0) {
        cell.textLabel.text = self.app.bundleId;
        cell.detailTextLabel.text = [self.app.appPath stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
        cell.imageView.image = [UIImage systemImageNamed:@"app.badge"];
        cell.imageView.tintColor = [SPTheme accent];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.detailTextLabel.numberOfLines = 1;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        return cell;
    }
    if (ip.section == 1) {
        if (ip.row == (NSInteger)self.plugins.count) {
            cell.textLabel.text = @"添加插件…";
            cell.textLabel.textColor = [SPTheme accent];
            cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
            cell.imageView.tintColor = [SPTheme accent];
        } else {
            SPTrollPlugin *p = self.plugins[ip.row];
            cell.textLabel.text = p.name;
            cell.detailTextLabel.text = p.path.stringByDeletingLastPathComponent;
            cell.imageView.image = [UIImage systemImageNamed:@"shippingbox.fill"];
            cell.imageView.tintColor = [SPTheme info];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = p.enabled;
            sw.tag = 8000 + ip.row;
            [sw addTarget:self action:@selector(togglePlugin:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        return cell;
    }
    if (ip.section == 2) {
        NSArray *titles = @[@"弱加载（--weak）", @"CoreTrust 绕过", @"注入后 ldid 补签"];
        cell.textLabel.text = titles[ip.row];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.tag = 8100 + ip.row;
        sw.on = ip.row == 0 ? self.weakLoad : (ip.row == 1 ? self.coreTrust : self.wantLdid);
        [sw addTarget:self action:@selector(toggleOption:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (ip.row == 0) {
        cell.textLabel.text = @"预览注入命令";
        cell.imageView.image = [UIImage systemImageNamed:@"list.bullet.rectangle"];
        cell.imageView.tintColor = [SPTheme info];
    } else {
        cell.textLabel.text = @"开始注入";
        cell.textLabel.textColor = [SPTheme accent];
        cell.imageView.image = [UIImage systemImageNamed:@"syringe.fill"];
        cell.imageView.tintColor = [SPTheme accent];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)togglePlugin:(UISwitch *)sw {
    NSInteger i = sw.tag - 8000;
    if (i >= 0 && i < (NSInteger)self.plugins.count) self.plugins[i].enabled = sw.isOn;
}

- (void)toggleOption:(UISwitch *)sw {
    NSInteger i = sw.tag - 8100;
    if (i == 0) self.weakLoad = sw.isOn;
    else if (i == 1) self.coreTrust = sw.isOn;
    else self.wantLdid = sw.isOn;
    [SPMotion hapticLight];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        if (ip.row == (NSInteger)self.plugins.count) [self addPlugin];
        else {
            SPTrollPlugin *p = self.plugins[ip.row];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:p.name
                message:p.path preferredStyle:UIAlertControllerStyleActionSheet];
            [a addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                [self.plugins removeObjectAtIndex:ip.row];
                [self.table reloadData];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            a.popoverPresentationController.sourceView = tv;
            [self presentViewController:a animated:YES completion:nil];
        }
        return;
    }
    if (ip.section == 3) {
        if (ip.row == 0) [self preview];
        else [self runInjection];
    }
}

#pragma mark 插件

- (void)addPlugin {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加插件" message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"从文件选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:@[@"public.data", @"public.item"] inMode:UIDocumentPickerModeImport];
        p.delegate = self;
        p.allowsMultipleSelection = YES;
        [self.navigationController presentViewController:p animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"从收件箱导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
            initWithRootPath:[[SPStore shared] inboxDirectory] pickMode:YES fileFilters:nil
                      onPick:^(NSString *path, BOOL isDir) { if (!isDir) [self append:path]; }];
        [self.navigationController pushViewController:b animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) [self append:u.path];
}

- (void)append:(NSString *)path {
    for (NSString *ext in @[@"dylib", @"framework", @"bundle", @"deb", @"zip"]) {
        if ([path.pathExtension.lowercaseString isEqualToString:ext]) {
            SPTrollPlugin *p = [SPTrollPlugin new];
            p.path = path;
            p.name = path.lastPathComponent;
            p.enabled = YES;
            [self.plugins addObject:p];
            [SPMotion hapticSuccess];
            [self.table reloadData];
            return;
        }
    }
    [self alert:@"不支持的类型" message:@"只支持 dylib / framework / bundle / deb / zip"];
}

#pragma mark 注入

- (NSArray<SPTrollPlugin *> *)activePlugins {
    NSMutableArray *out = [NSMutableArray array];
    for (SPTrollPlugin *p in self.plugins) if (p.enabled) [out addObject:p];
    return out;
}

- (NSMutableString *)commandScript {
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *reinRoot = [SPToolchain shared].reinRoot;
    [dirs addObjectsFromArray:@[
        SPToolchainInstallerBinDir(), [[[SPToolchain shared] scan] pathFor:SPToolchainComponentDarwin],
        [reinRoot stringByAppendingPathComponent:@"helpers"],
        [reinRoot stringByAppendingPathComponent:@"tools/theos-root/usr/bin"],
        @"/var/jb/usr/bin", @"/usr/bin", @"/usr/local/bin",
    ]];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *d in dirs) if (d.length) [clean addObject:d];

    NSString *insert = [SPUtil findExecutable:@[@"insert_dylib"] searchDirs:clean] ?: @"insert_dylib";
    NSString *ldid = [SPUtil findExecutable:@[@"ldid"] searchDirs:clean] ?: @"ldid";
    NSString *chown = [SPUtil findExecutable:@[@"chown"] searchDirs:clean] ?: @"chown";
    NSString *ct = [SPUtil findExecutable:@[@"ct_bypass"] searchDirs:clean];
    NSString *intool = [SPUtil findExecutable:@[@"install_name_tool"] searchDirs:clean];

    NSString *app = self.app.appPath;
    NSString *exeName = self.app.executable;
    if (!exeName.length) exeName = app.lastPathComponent.stringByDeletingPathExtension;
    NSString *exe = [app stringByAppendingPathComponent:exeName];
    NSArray *plugins = [self activePlugins];

    NSMutableString *s = [NSMutableString string];
    [s appendString:@"set -e\n"];
    [s appendString:@"say(){ printf '==> %s\\n' \"$1\"; }\n"];
    [s appendString:[NSString stringWithFormat:@"APP=%@\nEXE=%@\n", [SPUtil shellQuote:app], [SPUtil shellQuote:exe]]];
    [s appendString:[NSString stringWithFormat:@"INS=%@\nLID=%@\nOWN=%@\nINT=%@\n",
                     [SPUtil shellQuote:insert], [SPUtil shellQuote:ldid],
                     [SPUtil shellQuote:chown], [SPUtil shellQuote:intool]]];
    [s appendString:@"[ -x \"$INS\" ] || { echo \"缺少 insert_dylib\"; exit 3; }\n"];
    // 设备上没有 strings，用 grep -a；set -e 下命令不存在会静默退出（Rein 踩过）
    [s appendString:@"command -v grep >/dev/null 2>&1 || echo '[!] 没有 grep，幂等检查会被跳过'\n"];
    [s appendString:@"[ -f \"$EXE\" ] || { echo \"主二进制不存在: $EXE\"; exit 2; }\n"];
    [s appendString:@"say '备份'\nBK=\"${APP}.sparkbak\"\n[ -d \"$BK\" ] || cp -R \"$APP\" \"$BK\"\n"];
    [s appendString:@"TMP=$(mktemp -d /tmp/spark-inj.XXXXXX)\n"];

    // 解包 deb / zip
    for (SPTrollPlugin *p in plugins) {
        NSString *ext = p.path.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"deb"]) {
            [s appendString:[NSString stringWithFormat:
                @"say '解包 %@'\nmkdir -p \"$TMP/deb\"\n(cd \"$TMP/deb\" && (ar x %@ || true) && (tar xf data.tar.* || true)) || true\n",
                p.name, [SPUtil shellQuote:p.path]]];
        } else if ([ext isEqualToString:@"zip"]) {
            [s appendString:[NSString stringWithFormat:
                @"say '解包 %@'\nmkdir -p \"$TMP/zip\"\n(cd \"$TMP/zip\" && unzip -oq %@) || true\n",
                p.name, [SPUtil shellQuote:p.path]]];
        }
    }
    [s appendString:@"find \"$TMP\" -name '*.dylib' -o -name '*.framework' -o -name '*.bundle' 2>/dev/null | "
                 @"while read -r f; do cp -R \"$f\" \"$APP/\" 2>/dev/null || true; done\n"];

    // 复制 + 规范化安装名
    for (SPTrollPlugin *p in plugins) {
        NSString *ext = p.path.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"deb"] || [ext isEqualToString:@"zip"]) continue;
        NSString *base = p.name;
        NSString *dest = [base hasSuffix:@".framework"]
            ? [NSString stringWithFormat:@"\"$APP/Frameworks/%@\"", base]
            : [NSString stringWithFormat:@"\"$APP/%@\"", base];
        [s appendString:@"mkdir -p \"$APP/Frameworks\"\n"];
        [s appendString:[NSString stringWithFormat:@"say '复制 %@'\ncp -R %@ %@ 2>/dev/null || true\n",
                         base, [SPUtil shellQuote:p.path], dest]];
        if (intool.length) {
            [s appendString:[NSString stringWithFormat:
                @"[ -x \"$INT\" ] && \"$INT\" -id \"@executable_path/%@\" %@ 2>/dev/null || true\n", base, dest]];
        }
    }

    // 插入加载命令
    [s appendString:@"say '插入加载命令'\n"];
    NSMutableArray *loads = [NSMutableArray arrayWithObject:@"@executable_path/CydiaSubstrate.framework/CydiaSubstrate"];
    for (SPTrollPlugin *p in plugins) {
        NSString *ext = p.path.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"dylib"]) [loads addObject:[@"@executable_path/" stringByAppendingString:p.name]];
        else if ([ext isEqualToString:@"framework"]) {
            [loads addObject:[NSString stringWithFormat:@"@executable_path/Frameworks/%@/%@",
                              p.name, p.name.stringByDeletingPathExtension]];
        }
    }
    for (NSString *load in loads) {
        [s appendString:[NSString stringWithFormat:@"\"$INS\" %@ %@ \"$EXE\" >/dev/null 2>&1 || echo '[!] 插入失败: %@'\n",
                         self.weakLoad ? @"--weak --inplace" : @"--inplace", [SPUtil shellQuote:load], load]];
    }
    if (self.coreTrust && ct.length) {
        [s appendString:[NSString stringWithFormat:@"say 'CoreTrust 绕过'\n%@ \"$EXE\" 2>/dev/null || true\n", [SPUtil shellQuote:ct]]];
    }
    if (self.wantLdid) {
        [s appendString:@"say '补签'\n"];
        // insert_dylib 会移除旧 LC_CODE_SIGNATURE，这里必须重新生成 adhoc 签名
        [s appendString:@"\"$LID\" -S \"$EXE\" 2>/dev/null || true\n"];
        for (SPTrollPlugin *p in plugins) {
            if ([p.path.pathExtension.lowercaseString isEqualToString:@"dylib"]) {
                [s appendString:[NSString stringWithFormat:
                    @"\"$LID\" -S \"$APP/%@\" 2>/dev/null || true\n", p.name]];
            }
        }
    }
    [s appendString:@"\"$OWN\" -R mobile:mobile \"$APP\" 2>/dev/null || true\n"];
    [s appendString:@"rm -rf \"$TMP\"\nsay '完成'\necho \"已注入 $APP\"\n"];
    return s;
}

- (void)preview {
    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"inject-preview.sh"];
    [[self commandScript] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:e animated:YES];
}

- (void)runInjection {
    if (![self activePlugins].count) { [self alert:@"先添加插件" message:nil]; return; }
    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"inject.sh"];
    [[self commandScript] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    SPSession *session = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:NSTemporaryDirectory()];
    NSMutableString *log = [NSMutableString string];
    session.onLine = ^(NSString *line, SPLogLevel level) { [log appendString:line]; [log appendString:@"\n"]; };
    __weak typeof(self) weakSelf = self;
    session.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        if (r.exitCode == 0) [SPMotion hapticSuccess]; else [SPMotion hapticError];
        NSString *text = [NSString stringWithFormat:@"sh %@\n退出码 %ld\n\n%@\n%@",
                          path, (long)r.exitCode, log, r.stderrText ?: @""];
        [[SPBackground shared] endKeepAlive:@"inject"];
        NSString *p = [[SPStore shared] persistLogText:text jobId:@"inject"];
        SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:p];
        [self.navigationController pushViewController:e animated:YES];
        if (self.onFinished) self.onFinished();
    };
    session.timeout = 300;
    [[SPBackground shared] beginKeepAlive:@"inject"];
    [session runShell:[NSString stringWithFormat:@"sh %@", [SPUtil shellQuote:path]]];
    [self alert:@"注入已开始" message:@"已开启后台保活，切到后台也会继续执行。"];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
