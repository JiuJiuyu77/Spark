//
//  SPTrollViewController.m
//  巨魔注入器 —— HIG：分组列表（目标 / 插件 / 选项 / 执行），状态用 SF Symbols 徽章
//

#import "SPTrollViewController.h"
#import "SPTheme.h"
#import "SPStore.h"
#import "SPSession.h"
#import "SPCompat.h"
#import "SPToolchain.h"
#import "SPFileBrowserViewController.h"
#import "SPEditorViewController.h"
#import "SPLogView.h"

static NSString *const kSparkBundleRoot = @"/private/var/containers/Bundle/Application";

@interface SPTrollTarget : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *executable;
@property (nonatomic, copy) NSString *bundleId;
@end
@implementation SPTrollTarget
@end

typedef NS_ENUM(NSInteger, SPTrollSection) {
    SPTrollSectionTarget = 0,
    SPTrollSectionPlugins,
    SPTrollSectionOptions,
    SPTrollSectionRun,
    SPTrollSectionCount,
};

@interface SPTrollViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *toolStatus;
@property (nonatomic, strong) NSArray<SPTrollTarget *> *apps;
@property (nonatomic, strong) NSMutableArray<NSString *> *plugins;
@property (nonatomic, strong) SPTrollTarget *selectedApp;
@property (nonatomic, assign) BOOL weakLoad;
@property (nonatomic, assign) BOOL coreTrust;
@property (nonatomic, assign) BOOL wantLdid;
@property (nonatomic, copy) NSString *lastPlanText;
@end

@implementation SPTrollViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"注入";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.plugins = [NSMutableArray array];
    self.weakLoad = YES;
    self.coreTrust = YES;
    self.wantLdid = YES;

    [self buildStatusLabel];
    [self buildTable];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(reloadApps)];
    refresh.accessibilityLabel = @"刷新 App 列表";
    self.navigationItem.rightBarButtonItem = refresh;

    [self refreshTools];
    [self reloadApps];
}

- (void)buildStatusLabel {
    // HIG：状态说明放在列表 footer，不额外占一行
    self.toolStatus = [[UILabel alloc] init];
    self.toolStatus.font = [SPTheme caption];
    self.toolStatus.textColor = [SPTheme textDim];
    self.toolStatus.numberOfLines = 0;
    self.toolStatus.textAlignment = NSTextAlignmentCenter;
}

- (void)buildTable {
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
}

#pragma mark - 工具探测

- (void)refreshTools {
    SPToolchainScan *scan = [SPToolchain shared].scan;
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *reinRoot = [SPToolchain shared].reinRoot;
    [dirs addObject:[reinRoot stringByAppendingPathComponent:@"tools/reverse/bin"]];
    [dirs addObject:[reinRoot stringByAppendingPathComponent:@"tools/theos-root/usr/bin"]];
    [dirs addObject:[reinRoot stringByAppendingPathComponent:@"helpers"]];
    [dirs addObject:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"helpers"]];
    [dirs addObject:@"/var/jb/usr/bin"];
    [dirs addObject:@"/usr/bin"];
    (void)scan;

    NSArray *required = @[@"insert_dylib", @"ldid", @"chown"];
    NSMutableArray *status = [NSMutableArray array];
    NSInteger missing = 0;
    for (NSString *tool in required) {
        BOOL found = [SPUtil findExecutable:@[tool] searchDirs:dirs] != nil;
        [status addObject:[NSString stringWithFormat:@"%@ %@", found ? @"✓" : @"✕", tool]];
        if (!found) missing++;
    }
    BOOL ct = [SPUtil findExecutable:@[@"ct_bypass"] searchDirs:dirs] != nil;
    [status addObject:[NSString stringWithFormat:@"%@ ct_bypass", ct ? @"✓" : @"✕"]];

    self.toolStatus.text = missing
        ? [NSString stringWithFormat:@"注入工具链：%@\n缺少 %ld 个必需工具，注入会被拒绝。可把 Rein 的 helpers 目录指给「工具链」页。",
                                     [status componentsJoinedByString:@"  "], (long)missing]
        : [NSString stringWithFormat:@"注入工具链：%@%@", [status componentsJoinedByString:@"  "],
                                     ct ? @"" : @"\n没有 ct_bypass：注入后的 App 只能在越狱环境运行。"];
    self.toolStatus.textColor = missing ? [SPTheme danger] : [SPTheme textDim];
}

#pragma mark - 枚举 App

- (void)reloadApps {
    NSMutableArray *list = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in @[kSparkBundleRoot, @"/Applications", @"/var/jb/Applications"]) {
        NSArray *bids = [fm contentsOfDirectoryAtPath:root error:NULL] ?: @[];
        for (NSString *bid in bids) {
            NSString *dir = [root stringByAppendingPathComponent:bid];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
            NSArray *sub = [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[];
            for (NSString *name in sub) {
                if (![name hasSuffix:@".app"]) continue;
                NSString *appPath = [dir stringByAppendingPathComponent:name];
                NSString *plist = [appPath stringByAppendingPathComponent:@"Info.plist"];
                SPTrollTarget *t = [SPTrollTarget new];
                t.path = appPath;
                t.executable = [SPUtil stringFromPlistAtPath:plist key:@"CFBundleExecutable"
                                                     default:name.stringByDeletingPathExtension];
                t.bundleId = [SPUtil stringFromPlistAtPath:plist key:@"CFBundleIdentifier" default:bid];
                NSString *display = [SPUtil stringFromPlistAtPath:plist key:@"CFBundleDisplayName" default:nil];
                t.displayName = display.length ? display : name.stringByDeletingPathExtension;
                [list addObject:t];
            }
        }
    }
    [list sortUsingComparator:^NSComparisonResult(SPTrollTarget *a, SPTrollTarget *b) {
        if ([a.bundleId hasPrefix:@"com.HuQing.Spark"]) return NSOrderedAscending;
        if ([b.bundleId hasPrefix:@"com.HuQing.Spark"]) return NSOrderedDescending;
        return [a.displayName compare:b.displayName];
    }];
    self.apps = list;
    [self.table reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SPTrollSectionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SPTrollSectionTarget: return @"目标 App";
        case SPTrollSectionPlugins: return @"要注入的插件";
        case SPTrollSectionOptions: return @"注入选项";
        default: return @"执行";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SPTrollSectionTarget) {
        return self.toolStatus.text;
    }
    if (s == SPTrollSectionPlugins) {
        return @"支持 dylib / framework / bundle，也支持直接给 .deb / .zip（会自动解包）。";
    }
    if (s == SPTrollSectionOptions) {
        return @"注入会修改 App 本体，脚本第一步会自动备份为 .sparkbak。";
    }
    return self.lastPlanText.length ? self.lastPlanText : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SPTrollSectionTarget: return self.apps.count ? (NSInteger)self.apps.count : 1;
        case SPTrollSectionPlugins: return (NSInteger)self.plugins.count + 1;
        case SPTrollSectionOptions: return 3;
        default: return 2;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;

    switch (ip.section) {
        case SPTrollSectionTarget: {
            if (!self.apps.count) {
                cell.textLabel.text = @"没有找到 App";
                cell.detailTextLabel.text = @"需要越狱环境才能枚举 /private/var/containers/Bundle/Application";
                cell.detailTextLabel.textColor = [SPTheme danger];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
                cell.imageView.tintColor = [SPTheme warn];
                break;
            }
            SPTrollTarget *t = self.apps[ip.row];
            cell.textLabel.text = t.displayName;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", t.bundleId, t.executable];
            cell.imageView.image = [UIImage systemImageNamed:(t == self.selectedApp) ? @"largecircle.fill.circle" : @"circle"];
            cell.imageView.tintColor = (t == self.selectedApp) ? [SPTheme accent] : [SPTheme textDim];
            break;
        }
        case SPTrollSectionPlugins: {
            if (ip.row == (NSInteger)self.plugins.count) {
                cell.textLabel.text = @"添加插件…";
                cell.textLabel.textColor = [SPTheme accent];
                cell.detailTextLabel.text = @"从文件 App 或 Rein 市场目录选";
                cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
                cell.imageView.tintColor = [SPTheme accent];
                break;
            }
            NSString *p = self.plugins[ip.row];
            cell.textLabel.text = p.lastPathComponent;
            cell.textLabel.textColor = [SPTheme text];
            cell.detailTextLabel.text = [p stringByDeletingLastPathComponent];
            cell.imageView.image = [UIImage systemImageNamed:[self symbolForPlugin:p]];
            cell.imageView.tintColor = [SPTheme info];
            break;
        }
        case SPTrollSectionOptions: {
            NSArray *titles = @[@"弱加载（--weak）", @"CoreTrust 绕过", @"注入后 ldid 补签"];
            cell.textLabel.text = titles[ip.row];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.tag = 5000 + ip.row;
            sw.on = ip.row == 0 ? self.weakLoad : (ip.row == 1 ? self.coreTrust : self.wantLdid);
            [sw addTarget:self action:@selector(toggleOption:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.imageView.image = [UIImage systemImageNamed:ip.row == 0 ? @"link.badge.plus"
                                           : (ip.row == 1 ? @"checkmark.shield" : @"signature")];
            cell.imageView.tintColor = [SPTheme textDim];
            break;
        }
        default: {
            if (ip.row == 0) {
                cell.textLabel.text = @"预览注入计划";
                cell.imageView.image = [UIImage systemImageNamed:@"list.bullet.rectangle"];
                cell.imageView.tintColor = [SPTheme info];
            } else {
                cell.textLabel.text = @"开始注入";
                cell.textLabel.textColor = [SPTheme accent];
                cell.imageView.image = [UIImage systemImageNamed:@"syringe.fill"];
                cell.imageView.tintColor = [SPTheme accent];
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
    }
    return cell;
}

- (NSString *)symbolForPlugin:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"deb"]) return @"shippingbox.fill";
    if ([ext isEqualToString:@"zip"]) return @"archivebox.fill";
    if ([ext isEqualToString:@"framework"]) return @"cube.box.fill";
    if ([ext isEqualToString:@"bundle"]) return @"folder.fill";
    return @"shippingbox";
}

- (void)toggleOption:(UISwitch *)sw {
    NSInteger i = sw.tag - 5000;
    if (i == 0) self.weakLoad = sw.isOn;
    else if (i == 1) self.coreTrust = sw.isOn;
    else self.wantLdid = sw.isOn;
    [SPMotion hapticLight];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];

    if (ip.section == SPTrollSectionTarget) {
        if (!self.apps.count) return;
        self.selectedApp = self.apps[ip.row];
        [tv reloadSections:[NSIndexSet indexSetWithIndex:SPTrollSectionTarget]
         withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    if (ip.section == SPTrollSectionPlugins) {
        if (ip.row == (NSInteger)self.plugins.count) { [self addPlugin]; return; }
        NSString *p = self.plugins[ip.row];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:p.lastPathComponent
            message:p.stringByDeletingLastPathComponent preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [self.plugins removeObjectAtIndex:ip.row];
            [tv reloadData];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = tv;
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if (ip.section == SPTrollSectionRun) {
        if (ip.row == 0) [self previewPlan];
        else [self confirmInject];
    }
}

#pragma mark - 插件选择

- (void)addPlugin {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加插件" message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"从文件 App 选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:@[@"public.data", @"public.item"] inMode:UIDocumentPickerModeImport];
        picker.delegate = self;
        picker.allowsMultipleSelection = YES;
        [self.navigationController presentViewController:picker animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"浏览插件目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *root = @"/var/mobile/Documents/Rein/market";
        if (![[NSFileManager defaultManager] fileExistsAtPath:root]) root = NSHomeDirectory();
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:root
                                                                                 pickMode:YES fileFilters:nil
                                                                                      onPick:^(NSString *path, BOOL isDir) {
            if (!isDir) [self appendPlugin:path];
        }];
        [self.navigationController pushViewController:b animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) [self appendPlugin:url.path];
}

- (void)appendPlugin:(NSString *)path {
    if (!path.length) return;
    BOOL ok = NO;
    for (NSString *ext in @[@"dylib", @"framework", @"bundle", @"deb", @"zip"]) {
        if ([path.pathExtension.lowercaseString isEqualToString:ext]) { ok = YES; break; }
    }
    if (!ok) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"不支持的类型"
            message:@"只支持 dylib / framework / bundle / deb / zip" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [self.plugins addObject:path];
    [SPMotion hapticSuccess];
    [self.table reloadData];
}

#pragma mark - 计划与执行

- (NSString *)planText {
    if (!self.selectedApp) return @"先选一个目标 App";
    if (!self.plugins.count) return @"再添加至少一个插件";

    NSMutableString *s = [NSMutableString string];
    NSInteger i = 1;
    [s appendFormat:@"%2ld. 备份 %@ → .sparkbak\n", (long)i++, self.selectedApp.displayName];
    for (NSString *p in self.plugins) {
        NSString *ext = p.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"deb"] || [ext isEqualToString:@"zip"]) {
            [s appendFormat:@"%2ld. 解包 %@ 并取出插件\n", (long)i++, p.lastPathComponent];
        } else if ([ext isEqualToString:@"bundle"]) {
            [s appendFormat:@"%2ld. 复制资源包 %@\n", (long)i++, p.lastPathComponent];
        } else {
            [s appendFormat:@"%2ld. 复制 %@ 并规范化安装路径\n", (long)i++, p.lastPathComponent];
        }
    }
    [s appendFormat:@"%2ld. 复制 CydiaSubstrate.framework\n", (long)i++];
    [s appendFormat:@"%2ld. insert_dylib %@ 插入加载命令\n", (long)i++, self.weakLoad ? @"--weak" : @""];
    if (self.coreTrust) [s appendFormat:@"%2ld. ct_bypass 做 CoreTrust 绕过\n", (long)i++];
    if (self.wantLdid) [s appendFormat:@"%2ld. ldid -S 补签\n", (long)i++];
    [s appendFormat:@"%2ld. chown -R mobile:mobile\n", (long)i++];
    return s;
}

- (void)previewPlan {
    self.lastPlanText = [self planText];
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:SPTrollSectionRun]
             withRowAnimation:UITableViewRowAnimationAutomatic];

    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"troll-plan.txt"];
    [self.lastPlanText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:e animated:YES];
}

- (void)confirmInject {
    if (!self.selectedApp) { [self alert:@"先选目标 App" message:nil]; return; }
    if (!self.plugins.count) { [self alert:@"先添加插件" message:nil]; return; }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"确认注入"
        message:[NSString stringWithFormat:@"将修改：\n%@\n\n原文件会备份为 .sparkbak，可随时恢复。", self.selectedApp.path]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"注入" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [self runInjection];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runInjection {
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *reinRoot = [SPToolchain shared].reinRoot;
    [dirs addObjectsFromArray:@[
        [reinRoot stringByAppendingPathComponent:@"tools/reverse/bin"],
        [reinRoot stringByAppendingPathComponent:@"tools/theos-root/usr/bin"],
        [reinRoot stringByAppendingPathComponent:@"helpers"],
        [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"helpers"],
        @"/var/jb/usr/bin", @"/usr/bin", @"/usr/local/bin",
    ]];
    NSString *insertDylib = [SPUtil findExecutable:@[@"insert_dylib"] searchDirs:dirs];
    NSString *ldid = [SPUtil findExecutable:@[@"ldid"] searchDirs:dirs];
    NSString *chown = [SPUtil findExecutable:@[@"chown"] searchDirs:dirs];
    NSString *ctBypass = [SPUtil findExecutable:@[@"ct_bypass"] searchDirs:dirs];
    NSString *installNameTool = [SPUtil findExecutable:@[@"install_name_tool"] searchDirs:dirs];

    if (!insertDylib) { [self alert:@"缺少 insert_dylib" message:@"可从 Rein 的 helpers 目录复制一份过来"]; return; }

    SPTrollTarget *app = self.selectedApp;
    NSString *appPath = app.path;
    NSString *exe = [appPath stringByAppendingPathComponent:app.executable];

    NSMutableString *script = [NSMutableString string];
    [script appendString:@"set -e\n"];
    [script appendString:@"say(){ printf '==> %s\\n' \"$1\"; }\n"];
    [script appendString:[NSString stringWithFormat:@"APP=%@\n", [SPUtil shellQuote:appPath]]];
    [script appendString:[NSString stringWithFormat:@"EXE=%@\n", [SPUtil shellQuote:exe]]];
    [script appendString:[NSString stringWithFormat:@"INS=%@; LID=%@; OWN=%@\n",
        [SPUtil shellQuote:insertDylib],
        [SPUtil shellQuote:ldid ?: @""],
        [SPUtil shellQuote:chown ?: @""]]];
    [script appendString:@"[ -f \"$EXE\" ] || { echo \"主二进制不存在: $EXE\"; exit 2; }\n"];
    [script appendString:@"say '备份原 App'\n"];
    [script appendString:@"BK=\"${APP}.sparkbak\"; [ -d \"$BK\" ] || cp -R \"$APP\" \"$BK\"\n"];
    [script appendString:@"TMP=$(mktemp -d /tmp/spark-inject.XXXXXX)\n"];

    // 1) deb / zip 先解
    for (NSString *p in self.plugins) {
        NSString *ext = p.pathExtension.lowercaseString;
        NSString *q = [SPUtil shellQuote:p];
        if ([ext isEqualToString:@"deb"]) {
            [script appendString:[NSString stringWithFormat:
                @"say '解包 %@'\nmkdir -p \"$TMP/deb\"\n"
                 "(cd \"$TMP/deb\" && (ar x %@ 2>/dev/null || true) && "
                 "(tar xf data.tar.* 2>/dev/null || (gzip -dc data.tar.gz 2>/dev/null | tar xf - 2>/dev/null))) || true\n",
                p.lastPathComponent, q]];
        } else if ([ext isEqualToString:@"zip"]) {
            [script appendString:[NSString stringWithFormat:
                @"say '解包 %@'\nmkdir -p \"$TMP/zip\"\n(cd \"$TMP/zip\" && unzip -oq %@ 2>/dev/null) || true\n",
                p.lastPathComponent, q]];
        }
    }

    // 2) 复制插件
    [script appendString:@"say '复制插件'\n"];
    [script appendString:@"find \"$TMP\" -name '*.dylib' -o -name '*.framework' -o -name '*.bundle' 2>/dev/null | "
                         @"while read -r f; do cp -R \"$f\" \"$APP/\" 2>/dev/null || true; done\n"];
    for (NSString *p in self.plugins) {
        NSString *ext = p.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"deb"] || [ext isEqualToString:@"zip"]) continue;
        NSString *base = p.lastPathComponent;
        NSString *dest = [base hasSuffix:@".framework"]
            ? [NSString stringWithFormat:@"\"$APP/Frameworks/%@\"", base]
            : [NSString stringWithFormat:@"\"$APP/%@\"", base];
        [script appendString:@"mkdir -p \"$APP/Frameworks\"\n"];
        [script appendString:[NSString stringWithFormat:@"cp -R %@ %@ 2>/dev/null || true\n", [SPUtil shellQuote:p], dest]];
        if (installNameTool) {
            [script appendString:[NSString stringWithFormat:@"[ -x %@ ] && \"%@\" -id \"@executable_path/%@\" %@ 2>/dev/null || true\n",
                [SPUtil shellQuote:installNameTool], [SPUtil shellQuote:installNameTool], base, dest]];
        }
    }

    // 3) 插入加载命令
    [script appendString:@"say '注入加载命令'\n"];
    NSMutableArray *loads = [NSMutableArray arrayWithObject:@"@executable_path/CydiaSubstrate.framework/CydiaSubstrate"];
    for (NSString *p in self.plugins) {
        NSString *ext = p.pathExtension.lowercaseString;
        NSString *base = p.lastPathComponent;
        if ([ext isEqualToString:@"dylib"]) [loads addObject:[@"@executable_path/" stringByAppendingString:base]];
        else if ([ext isEqualToString:@"framework"]) {
            [loads addObject:[NSString stringWithFormat:@"@executable_path/Frameworks/%@/%@", base, base.stringByDeletingPathExtension]];
        }
    }
    for (NSString *load in loads) {
        [script appendString:[NSString stringWithFormat:@"\"$INS\" %@ %@ \"$EXE\" >/dev/null 2>&1 || echo '[!] 插入失败：%@'\n",
            self.weakLoad ? @"--weak --inplace" : @"--inplace", [SPUtil shellQuote:load], load]];
    }

    if (self.coreTrust && ctBypass) {
        [script appendString:[NSString stringWithFormat:@"say 'CoreTrust 绕过'\n%@ \"$EXE\" 2>/dev/null || echo '[!] ct_bypass 失败（需越狱环境）'\n",
            [SPUtil shellQuote:ctBypass]]];
    }
    if (self.wantLdid && ldid) {
        [script appendString:[NSString stringWithFormat:@"say '补签'\n%@ -S \"$EXE\" 2>/dev/null || true\n", [SPUtil shellQuote:ldid]]];
    }
    if (chown) {
        [script appendString:[NSString stringWithFormat:@"say '改属主'\n%@ -R mobile:mobile \"$APP\" 2>/dev/null || true\n", [SPUtil shellQuote:chown]]];
    }
    [script appendString:@"rm -rf \"$TMP\"\nsay '完成'\necho \"已注入：$APP\"\necho \"备份：$BK\"\n"];

    NSString *scriptPath = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"troll-inject.sh"];
    [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    SPSession *session = [[SPSession alloc] initWithEnvironment:@{@"PATH": [dirs componentsJoinedByString:@":"]}
                                              workingDirectory:NSTemporaryDirectory()];
    NSMutableString *log = [NSMutableString string];
    session.onLine = ^(NSString *line, SPLogLevel level) {
        [log appendString:line];
        [log appendString:@"\n"];
    };
    __weak typeof(self) weakSelf = self;
    session.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        if (r.exitCode == 0) [SPMotion hapticSuccess]; else [SPMotion hapticError];
        NSString *text = [NSString stringWithFormat:@"命令  sh %@\n退出码 %ld\n\n%@\n%@",
                          scriptPath, (long)r.exitCode, log, r.stderrText ?: @""];
        NSString *p = [[SPStore shared] persistLogText:text jobId:@"troll-inject"];
        SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:p];
        [self.navigationController pushViewController:e animated:YES];
    };
    session.timeout = 300;
    [session runShell:[NSString stringWithFormat:@"sh %@", [SPUtil shellQuote:scriptPath]]];
    [self alert:@"注入已开始" message:@"过程日志会在完成后打开，请先不要退出 App。"];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
