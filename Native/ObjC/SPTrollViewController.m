//
//  SPTrollViewController.m
//

#import "SPTrollViewController.h"
#import "SPTheme.h"
#import "SPStore.h"
#import "SPSession.h"
#import "SPCompat.h"
#import "SPFileBrowserViewController.h"
#import "SPEditorViewController.h"
#import "SPLogView.h"

static NSString *const kSparkBundlePath = @"/private/var/containers/Bundle/Application";

@interface SPTrollTarget : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *path;         // .app 绝对路径
@property (nonatomic, copy) NSString *executable;   // 主二进制名
@property (nonatomic, copy) NSString *bundleId;
@end
@implementation SPTrollTarget
@end

@interface SPTrollViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *toolStatus;
@property (nonatomic, strong) NSArray<SPTrollTarget *> *apps;
@property (nonatomic, strong) NSMutableArray<NSString *> *plugins;
@property (nonatomic, strong) SPTrollTarget *selectedApp;
@property (nonatomic, assign) BOOL weakLoad;
@property (nonatomic, assign) BOOL coreTrust;
@property (nonatomic, assign) BOOL wantLdid;
@property (nonatomic, strong) UIButton *injectButton;
@property (nonatomic, strong) UILabel *summaryLabel;
// 字典里没有的 key 用 ivar 存，避免依赖 ProjectKit 的 JS 实现
@property (nonatomic, copy) NSString *lastPlanText;
@end

@implementation SPTrollViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"巨魔注入器";
    self.plugins = [NSMutableArray array];
    self.weakLoad = YES;
    self.coreTrust = YES;
    self.wantLdid = YES;

    [self buildHeader];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.toolStatus.bottomAnchor constant:4],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(reloadApps)];

    [self refreshTools];
    [self reloadApps];
}

- (void)buildHeader {
    self.toolStatus = [[UILabel alloc] init];
    self.toolStatus.font = [SPTheme monoFont:10];
    self.toolStatus.textColor = [SPTheme textDim];
    self.toolStatus.numberOfLines = 2;
    self.toolStatus.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.toolStatus];
    [NSLayoutConstraint activateConstraints:@[
        [self.toolStatus.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.toolStatus.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.toolStatus.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

#pragma mark - 工具探测

- (void)refreshTools {
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *reinRoot = [[NSUserDefaults standardUserDefaults] objectForKey:@"Spark.reinRoot"];
    if (!reinRoot.length) reinRoot = @"/var/mobile/Documents/Rein";
    [dirs addObject:[reinRoot stringByAppendingPathComponent:@"tools/reverse/bin"]];
    [dirs addObject:[reinRoot stringByAppendingPathComponent:@"tools/theos-root/usr/bin"]];
    [dirs addObject:[reinRoot stringByAppendingPathComponent:@"helpers"]];
    [dirs addObject:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"helpers"]];
    [dirs addObject:@"/var/jb/usr/bin"];
    [dirs addObject:@"/usr/bin"];
    [dirs addObject:@"/usr/local/bin"];

    NSArray *required = @[@"insert_dylib", @"ldid", @"chown"];
    NSMutableArray *status = [NSMutableArray array];
    NSInteger missing = 0;
    for (NSString *tool in required) {
        NSString *found = [SPUtil findExecutable:@[tool] searchDirs:dirs];
        [status addObject:[NSString stringWithFormat:@"%@%@", found ? @"✓" : @"✗", tool]];
        if (!found) missing++;
    }
    NSString *ctBypass = [SPUtil findExecutable:@[@"ct_bypass"] searchDirs:dirs];
    [status addObject:[NSString stringWithFormat:@"%@ct_bypass", ctBypass ? @"✓" : @"✗"]];

    self.toolStatus.text = [NSString stringWithFormat:@"工具链：%@%@",
        [status componentsJoinedByString:@"  "],
        missing ? [NSString stringWithFormat:@"\n缺 %ld 个必需工具，注入会被拒绝", (long)missing] : @""];
    self.toolStatus.textColor = missing ? [SPTheme danger] : [SPTheme textDim];
}

#pragma mark - 枚举已安装的 App

- (void)reloadApps {
    NSMutableArray *list = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in @[kSparkBundlePath, @"/Applications", @"/var/jb/Applications"]) {
        NSArray *bids = [fm contentsOfDirectoryAtPath:root error:NULL] ?: @[];
        for (NSString *bid in bids) {
            NSString *dir = [root stringByAppendingPathComponent:bid];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
            // Bundle/Application/<UUID>/Xxx.app 或 Applications/Xxx.app
            NSArray *sub = [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[bid];
            for (NSString *name in sub) {
                if (![name hasSuffix:@".app"]) continue;
                NSString *appPath = [dir stringByAppendingPathComponent:name];
                NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                NSString *exe = [SPUtil stringFromPlistAtPath:plistPath key:@"CFBundleExecutable" default:name.stringByDeletingPathExtension];
                NSString *icon = [SPUtil stringFromPlistAtPath:plistPath key:@"CFBundleDisplayName" default:name.stringByDeletingPathExtension];
                SPTrollTarget *t = [SPTrollTarget new];
                t.path = appPath;
                t.executable = exe;
                t.bundleId = [SPUtil stringFromPlistAtPath:plistPath key:@"CFBundleIdentifier" default:bid];
                t.displayName = icon.length ? icon : name.stringByDeletingPathExtension;
                [list addObject:t];
            }
        }
    }
    // 按名字排序，顺带把 Spark 自己排前面方便调试
    [list sortUsingComparator:^NSComparisonResult(SPTrollTarget *a, SPTrollTarget *b) {
        if ([a.bundleId hasPrefix:@"com.HuQing.Spark"]) return NSOrderedAscending;
        if ([b.bundleId hasPrefix:@"com.HuQing.Spark"]) return NSOrderedDescending;
        return [a.displayName compare:b.displayName];
    }];
    self.apps = list;
    [self.table reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"目标 App", @"插件（dylib / framework / bundle / deb / zip）", @"注入选项", @"执行"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) return @"支持直接从 .deb / .zip 里取插件；注入前会自动备份原 App。";
    if (s == 3 && self.lastPlanText.length) return self.lastPlanText;
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case 0: return self.apps.count ? self.apps.count : 1;
        case 1: return self.plugins.count + 1;
        case 2: return 4;
        case 3: return 2;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    cell.backgroundColor = [SPTheme surface];
    cell.textLabel.textColor = [SPTheme text];
    cell.textLabel.font = [SPTheme uiFont:14 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [SPTheme textDim];
    cell.detailTextLabel.font = [SPTheme monoFont:10];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (ip.section == 0) {
        if (!self.apps.count) {
            cell.textLabel.text = @"没有找到 App（需要越狱环境）";
            cell.textLabel.textColor = [SPTheme danger];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        SPTrollTarget *t = self.apps[ip.row];
        cell.textLabel.text = t.displayName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", t.bundleId, t.executable];
        if (t == self.selectedApp) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = [SPTheme accent];
        }
    } else if (ip.section == 1) {
        if (ip.row == self.plugins.count) {
            cell.textLabel.text = @"＋ 添加插件…";
            cell.textLabel.textColor = [SPTheme accent];
            cell.detailTextLabel.text = @"从文件里选 dylib / framework / .deb / .zip";
        } else {
            NSString *p = self.plugins[ip.row];
            cell.textLabel.text = p.lastPathComponent;
            cell.detailTextLabel.text = p.stringByDeletingLastPathComponent;
            UISwitch *sw = nil; (void)sw;
        }
    } else if (ip.section == 2) {
        NSArray *titles = @[@"弱加载（--weak）", @"CoreTrust 绕过", @"注入后 ldid 补签", @"打包成 ipa"];
        cell.textLabel.text = titles[ip.row];
        if (ip.row < 3) {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.tag = 2000 + ip.row;
            sw.onTintColor = [SPTheme accent];
            sw.on = ip.row == 0 ? self.weakLoad : (ip.row == 1 ? self.coreTrust : self.wantLdid);
            [sw addTarget:self action:@selector(toggleOption:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.detailTextLabel.text = @"即将支持";
            cell.textLabel.textColor = [SPTheme textDim];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else {
        if (ip.row == 0) {
            cell.textLabel.text = @"预览注入计划";
            cell.textLabel.textColor = [SPTheme info];
        } else {
            cell.textLabel.text = @"开始注入";
            cell.textLabel.textColor = [SPTheme accent];
            cell.textLabel.font = [SPTheme uiFont:15 weight:UIFontWeightSemibold];
        }
    }
    return cell;
}

- (void)toggleOption:(UISwitch *)sw {
    NSInteger i = sw.tag - 2000;
    if (i == 0) self.weakLoad = sw.isOn;
    else if (i == 1) self.coreTrust = sw.isOn;
    else self.wantLdid = sw.isOn;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        if (!self.apps.count) return;
        self.selectedApp = self.apps[ip.row];
        [tv reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    if (ip.section == 1) {
        if (ip.row == self.plugins.count) { [self addPlugin]; return; }
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
    if (ip.section == 3) {
        if (ip.row == 0) [self previewPlan];
        else [self confirmInject];
    }
}

#pragma mark - 插件选择

- (void)addPlugin {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加插件"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"从文件 App 选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self presentDocumentPicker];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"浏览 Rein 的插件市场目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
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

- (void)presentDocumentPicker {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data", @"public.item"]
                       inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    // 用当前这个 tab 自己的导航控制器 present，避免和外层 UITabBarController 抢 modal
    [self.navigationController presentViewController:picker animated:YES completion:nil];
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
        [self alert:@"不支持的类型" message:[NSString stringWithFormat:@"%@ 不是 dylib/framework/bundle/deb/zip", path.lastPathComponent]];
        return;
    }
    [self.plugins addObject:path];
    [self.table reloadData];
}

#pragma mark - 计划与执行

/// 生成与 ProjectKit/src/trollinject.mjs 的 planInjection 等价的计划文本。
/// 纯字符串拼装，不依赖 JS 运行时，保证真机上零依赖。
- (NSString *)planText {
    if (!self.selectedApp) return @"先选一个目标 App";
    if (!self.plugins.count) return @"先添加至少一个插件";

    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"目标：%@（%@）\n", self.selectedApp.path, self.selectedApp.executable];
    NSInteger i = 1;
    [s appendFormat:@"%2ld. 备份 %@ → %@.sparkbak\n", (long)i++, self.selectedApp.displayName, self.selectedApp.displayName];
    for (NSString *p in self.plugins) {
        NSString *name = p.lastPathComponent;
        NSString *ext = p.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"deb"] || [ext isEqualToString:@"zip"]) {
            [s appendFormat:@"%2ld. 解包 %@ → 取出 dylib / framework / bundle\n", (long)i++, name];
            [s appendFormat:@"%2ld. 规范化安装路径 + ldid 补签\n", (long)i++];
        } else if ([ext isEqualToString:@"bundle"]) {
            [s appendFormat:@"%2ld. 复制资源包 %@ → App 根目录\n", (long)i++, name];
        } else {
            [s appendFormat:@"%2ld. 复制 %@ → App 根目录（@executable_path）\n", (long)i++, name];
        }
    }
    [s appendFormat:@"%2ld. 复制 CydiaSubstrate.framework（tweak 加载器）\n", (long)i++];
    [s appendFormat:@"%2ld. insert_dylib %@ 插入加载命令\n", (long)i++, self.weakLoad ? @"--weak" : @"（强加载）"];
    if (self.coreTrust) [s appendFormat:@"%2ld. ct_bypass 做 CoreTrust 绕过\n", (long)i++];
    if (self.wantLdid) [s appendFormat:@"%2ld. ldid -S 整体补签\n", (long)i++];
    [s appendFormat:@"%2ld. chown -R mobile:mobile\n", (long)i++];
    return s;
}

- (void)previewPlan {
    self.lastPlanText = [self planText];
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationAutomatic];

    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"troll-plan.txt"];
    [self.lastPlanText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:e animated:YES];
}

- (void)confirmInject {
    if (!self.selectedApp) { [self alert:@"先选目标 App" message:nil]; return; }
    if (!self.plugins.count) { [self alert:@"先添加插件" message:nil]; return; }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"确认注入"
        message:[NSString stringWithFormat:@"将修改 %@\n（原文件会备份为 .sparkbak）", self.selectedApp.path]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"注入" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [self runInjection];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runInjection {
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *reinRoot = @"/var/mobile/Documents/Rein";
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

    if (!insertDylib) { [self alert:@"缺少 insert_dylib" message:@"可以从 Rein 的 helpers 目录复制一份过来"]; return; }

    SPTrollTarget *app = self.selectedApp;
    NSString *appPath = app.path;
    NSString *exe = [appPath stringByAppendingPathComponent:app.executable];

    NSMutableString *script = [NSMutableString string];
    [script appendString:@"set -e\n"];
    [script appendString:@"say(){ printf '\\033[1;36m==> %s\\033[0m\\n' \"$1\"; }\n"];
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

    // 1) 逐个插件：deb/zip 先解包
    NSMutableArray *pluginScripts = [NSMutableArray array];
    for (NSString *p in self.plugins) {
        NSString *q = [SPUtil shellQuote:p];
        NSString *ext = p.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"deb"]) {
            [pluginScripts addObject:[NSString stringWithFormat:
                @"say '解包 deb %@'\n"
                @"mkdir -p \"$TMP/deb\"\n"
                @"cd \"$TMP/deb\" && (ar x %@ 2>/dev/null || true) && "
                @"(tar xf data.tar.* 2>/dev/null || (gzip -dc data.tar.gz 2>/dev/null | tar xf - 2>/dev/null)) || true\n"
                @"cd - >/dev/null\n", p.lastPathComponent, q]];
        } else if ([ext isEqualToString:@"zip"]) {
            [pluginScripts addObject:[NSString stringWithFormat:
                @"say '解包 zip %@'\nmkdir -p \"$TMP/zip\"\n"
                @"(cd \"$TMP/zip\" && (unzip -oq %@ 2>/dev/null || copyfiles -u 1 %@ . 2>/dev/null)) || true\n",
                p.lastPathComponent, q, q]];
        }
    }
    for (NSString *ps in pluginScripts) [script appendString:ps];

    // 2) 复制插件到 App 目录
    [script appendString:@"say '复制插件'\n"];
    for (NSString *p in self.plugins) {
        NSString *ext = p.pathExtension.lowercaseString;
        NSString *base = p.lastPathComponent;
        if ([ext isEqualToString:@"deb"] || [ext isEqualToString:@"zip"]) {
            [script appendString:
                @"find \"$TMP\" -name '*.dylib' -o -name '*.framework' -o -name '*.bundle' 2>/dev/null | "
                @"while read -r f; do cp -R \"$f\" \"$APP/\" 2>/dev/null || true; "
                @"case \"$f\" in *.dylib) [ -n \"$LID\" ] && \"$LID\" -S \"$APP/$(basename \"$f\")\" || true;; esac; done\n"];
        } else if ([ext isEqualToString:@"bundle"]) {
            [script appendString:[NSString stringWithFormat:
                @"cp -R %@ \"$APP/\" 2>/dev/null || true\n", [SPUtil shellQuote:p]]];
        } else {
            // dylib / framework：复制 + 规范化安装名 + 补签
            NSString *dest = [base hasSuffix:@".framework"]
                ? [NSString stringWithFormat:@"\"$APP/Frameworks/%@\"", base]
                : [NSString stringWithFormat:@"\"$APP/%@\"", base];
            [script appendString:[NSString stringWithFormat:
                @"mkdir -p \"$APP/Frameworks\"\ncp -R %@ %@ 2>/dev/null || true\n",
                [SPUtil shellQuote:p], dest]];
            if (installNameTool) {
                [script appendString:[NSString stringWithFormat:
                    @"[ -n \"%@\" ] && [ -n \"$LID\" ] && [ -x %@ ] && ("
                    @"if [ -d %@ ]; then BIN=%@/%@; else BIN=%@; fi; "
                    @"NAME=$(basename \"$BIN\"); \"%@\" -id \"@executable_path/%@\" \"$BIN\" 2>/dev/null || true; "
                    @"\"$LID\" -S \"$BIN\" 2>/dev/null || true)\n",
                    installNameTool, [SPUtil shellQuote:installNameTool],
                    dest, dest, [base stringByDeletingPathExtension],
                    dest,
                    [SPUtil shellQuote:installNameTool], base]];
            }
        }
    }

    // 3) 逐个给 App 主二进制插入加载命令
    [script appendString:@"say '注入加载命令'\n"];
    NSMutableArray *loads = [NSMutableArray array];
    [loads addObject:@"@executable_path/CydiaSubstrate.framework/CydiaSubstrate"];
    for (NSString *p in self.plugins) {
        NSString *ext = p.pathExtension.lowercaseString;
        NSString *base = p.lastPathComponent;
        if ([ext isEqualToString:@"dylib"]) [loads addObject:[@"@executable_path/" stringByAppendingString:base]];
        else if ([ext isEqualToString:@"framework"]) {
            [loads addObject:[NSString stringWithFormat:@"@executable_path/Frameworks/%@/%@",
                              base, base.stringByDeletingPathExtension]];
        }
    }
    for (NSString *load in loads) {
        [script appendString:[NSString stringWithFormat:
            @"\"$INS\" %@ %@ \"$EXE\" >/dev/null 2>&1 || echo '[!] 插入失败：%@'\n",
            self.weakLoad ? @"--weak --inplace" : @"--inplace",
            [SPUtil shellQuote:load], load]];
    }

    if (self.coreTrust && ctBypass) {
        [script appendString:[NSString stringWithFormat:
            @"say 'CoreTrust 绕过'\n%@ \"$EXE\" 2>/dev/null || echo '[!] ct_bypass 执行失败（仅越狱环境可运行）'\n",
            [SPUtil shellQuote:ctBypass]]];
    }
    if (self.wantLdid && ldid) {
        [script appendString:[NSString stringWithFormat:
            @"say '整体补签'\n%@ -S \"$EXE\" 2>/dev/null || echo '[!] ldid 补签失败'\n",
            [SPUtil shellQuote:ldid]]];
    }
    if (chown) {
        [script appendString:[NSString stringWithFormat:
            @"say '改属主'\n%@ -R mobile:mobile \"$APP\" 2>/dev/null || true\n",
            [SPUtil shellQuote:chown]]];
    }
    [script appendString:@"rm -rf \"$TMP\"\n"];
    [script appendString:@"say '完成'\necho \"已注入：$APP（备份 $BK）\"\n"];

    // 用临时文件跑，日志落到控制台
    NSString *scriptPath = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"troll-inject.sh"];
    [script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    SPSession *session = [[SPSession alloc] initWithEnvironment:@{@"PATH": [dirs componentsJoinedByString:@":"]}
                                              workingDirectory:NSTemporaryDirectory()];
    NSMutableString *log = [NSMutableString string];
    session.onLine = ^(NSString *line, SPLogLevel level) { [log appendString:line]; [log appendString:@"\n"]; };
    __weak typeof(self) weakSelf = self;
    session.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        NSString *text = [NSString stringWithFormat:
            @"命令：sh %@\n退出码：%ld\n\n%@\n%@",
            scriptPath, (long)r.exitCode, log, r.stderrText ?: @""];
        NSString *p = [[SPStore shared] persistLogText:text jobId:@"troll-inject"];
        SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:p];
        [self.navigationController pushViewController:e animated:YES];
    };
    session.timeout = 300;
    [session runShell:[NSString stringWithFormat:@"sh %@", [SPUtil shellQuote:scriptPath]]];
    [self alert:@"注入已开始" message:@"过程日志会在完成后打开。请勿退出 App。"];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
