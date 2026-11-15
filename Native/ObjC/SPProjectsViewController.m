//
//  SPProjectsViewController.m
//  项目列表 —— Apple HIG：大标题 + InsetGrouped 列表 + SF Symbols + 空状态引导
//

#import "SPProjectsViewController.h"
#import "SPTheme.h"
#import "SPStore.h"
#import "SPProjectViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchain.h"
#import "SPBuilder.h"
#import "SPCompat.h"
#import "SPModels.h"
#import "SPAnimationKit.h"

NSString *const SPOpenToolchainTabNotification = @"SPOpenToolchainTab";
NSString *const SPProjectCreatedNotification = @"SPProjectCreated";

@interface SPProjectsViewController () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) UIView *emptyState;
@end

@implementation SPProjectsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"项目";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    [self setupTable];
    [self setupSearch];
    [self setupNavItems];

    [self reloadAll];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadAll)
                                                 name:SPProjectCreatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadAll)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSArray *cells = self.table.visibleCells;
    if (cells.count) [SPAnimationKit stagger:cells offset:12];
}

#pragma mark - 布局

- (void)setupTable {
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 64;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

/// HIG：搜索放在导航栏下方，滚动时自动收起
- (void)setupSearch {
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索项目";
    self.search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}

- (void)setupNavItems {
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                        target:self action:@selector(addTapped)];
    add.accessibilityLabel = @"新建或导入项目";
    self.navigationItem.rightBarButtonItem = add;

    UIBarButtonItem *scan = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(reloadAll)];
    scan.accessibilityLabel = @"刷新项目列表";
    self.navigationItem.leftBarButtonItem = scan;
}

#pragma mark - 数据

- (void)reloadAll {
    NSMutableArray *all = [NSMutableArray arrayWithArray:[[SPStore shared] recentProjects]];

    NSString *root = [SPStore shared].projectsDirectory;
    NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    NSMutableSet *known = [NSMutableSet set];
    for (NSDictionary *d in all) [known addObject:d[@"path"]];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."]) continue;
        NSString *full = [root stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
        if (!isDir || [known containsObject:full]) continue;
        [all addObject:@{@"path": full, @"name": n, @"kind": @"", @"opened": @(0), @"summary": @""}];
    }

    // 过滤掉已不存在的路径（用户可能在文件 App 里删了）
    [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
        return [[NSFileManager defaultManager] fileExistsAtPath:d[@"path"] ?: @""];
    }]];

    if (self.filter.length) {
        [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
            return [d[@"name"] localizedCaseInsensitiveContainsString:self.filter];
        }]];
    }
    self.items = all;
    [self.table reloadData];
    [self updateEmptyState];

    // 工具链状态放在 section footer，不占列表空间
    [[SPToolchain shared] rescan];
}

- (void)updateEmptyState {
    if (self.items.count) {
        self.table.backgroundView = nil;
        return;
    }
    if (!self.emptyState) {
        UIView *v = [[UIView alloc] init];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"hammer"]];
        icon.tintColor = [SPTheme textDim];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *title = [[UILabel alloc] init];
        title.text = @"还没有项目";
        title.font = [SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
        title.textColor = [SPTheme text];
        title.textAlignment = NSTextAlignmentCenter;
        title.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *sub = [[UILabel alloc] init];
        sub.text = @"点右上角 ＋ 新建模板，或从磁盘导入已有的 Theos 工程。";
        sub.font = [SPTheme body];
        sub.textColor = [SPTheme textDim];
        sub.numberOfLines = 0;
        sub.textAlignment = NSTextAlignmentCenter;
        sub.translatesAutoresizingMaskIntoConstraints = NO;

        for (UIView *x in @[icon, title, sub]) [v addSubview:x];
        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-90],
            [icon.widthAnchor constraintEqualToConstant:48],
            [icon.heightAnchor constraintEqualToConstant:48],

            [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
            [title.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
            [title.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],

            [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [sub.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
            [sub.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],
        ]];
        self.emptyState = v;
    }
    self.table.backgroundView = self.emptyState;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.filter = sc.searchBar.text ?: @"";
    [self reloadAll];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.items.count ? @"最近项目" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    SPToolchainScan *scan = [SPToolchain shared].scan;
    NSArray *remedies = [scan remedies];
    if (remedies.count) return [remedies componentsJoinedByString:@"\n"];
    return [NSString stringWithFormat:@"工具链：%@", [scan summary]];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *const kCell = @"project";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCell];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCell];
    [SPTheme styleCell:cell];

    NSDictionary *d = self.items[ip.row];
    NSString *kind = d[@"kind"] ?: @"";
    NSString *path = [d[@"path"] stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];

    cell.textLabel.text = d[@"name"] ?: @"";
    cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightMedium];
    cell.detailTextLabel.text = kind.length
        ? [NSString stringWithFormat:@"%@ · %@", kind, path]
        : path;
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // HIG：用 SF Symbols 表达类型，扫一眼就知道是什么工程
    UIImage *icon = [UIImage systemImageNamed:[self symbolForKind:kind]];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
    iconView.tintColor = [SPTheme accent];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(0, 0, 28, 28);
    cell.imageView.image = icon;
    cell.imageView.tintColor = [SPTheme accent];
    (void)iconView;

    // 长按菜单（HIG 推荐 Context Menu，而不是长按弹 ActionSheet）
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)symbolForKind:(NSString *)kind {
    NSString *k = kind.lowercaseString;
    if ([k isEqualToString:@"tweak"]) return @"wand.and.stars";
    if ([k isEqualToString:@"app"] || [k isEqualToString:@"application"]) return @"app.badge";
    if ([k isEqualToString:@"library"]) return @"shippingbox";
    if ([k isEqualToString:@"tool"]) return @"hammer";
    if ([k isEqualToString:@"node"]) return @"curlybraces";
    return @"doc.text";
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (cell) {
        CGPoint p = [tv.panGestureRecognizer locationInView:cell.contentView];
        [SPAnimationKit rippleIn:cell.contentView at:p color:nil];
    }
    [self openProjectAtIndexPath:ip];
}

- (void)openProjectAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *d = self.items[ip.row];
    NSError *err = nil;
    SPProject *p = [SPProject projectAtPath:d[@"path"] error:&err];
    if (!p) {
        [self presentAlert:@"打不开这个项目" message:err.localizedDescription ?: @"目录可能已被删除"];
        return;
    }
    p.options = [[SPStore shared] optionsForProjectPath:p.path];
    [[SPStore shared] pushRecentProject:p];
    SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Context Menu（HIG）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    NSDictionary *d = self.items[ip.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIAction *remove = [UIAction actionWithTitle:@"从列表移除" image:[UIImage systemImageNamed:@"eye.slash"]
                                              identifier:nil handler:^(UIAction *a) {
            [[SPStore shared] removeRecentProjectAtPath:d[@"path"]];
            [self reloadAll];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;

        UIAction *copy = [UIAction actionWithTitle:@"复制路径" image:[UIImage systemImageNamed:@"doc.on.doc"]
                                           identifier:nil handler:^(UIAction *a) {
            UIPasteboard.generalPasteboard.string = d[@"path"];
            [SPMotion hapticSuccess];
        }];

        UIAction *openFolder = [UIAction actionWithTitle:@"在文件浏览中打开" image:[UIImage systemImageNamed:@"folder"]
                                                 identifier:nil handler:^(UIAction *a) {
            SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
                initWithRootPath:d[@"path"] pickMode:NO fileFilters:nil onPick:nil];
            [self.navigationController pushViewController:b animated:YES];
        }];
        return [UIMenu menuWithTitle:@"" children:@[openFolder, copy, remove]];
    }];
}

#pragma mark - 新建 / 导入

- (void)addTapped {
    [SPMotion hapticLight];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"新建或导入" message:nil
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"新建 Tweak 工程" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptNewProjectWithTemplate:@"tweak"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"新建 App 工程" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptNewProjectWithTemplate:@"application"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从磁盘导入目录…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pickDirectory];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickDirectory {
    SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:NSHomeDirectory()
                                                                              pickMode:YES fileFilters:nil
                                                                                onPick:^(NSString *path, BOOL isDir) {
        SPProject *p = [SPProject projectAtPath:path error:NULL];
        if (p) {
            p.options = [[SPStore shared] optionsForProjectPath:p.path];
            [[SPStore shared] pushRecentProject:p];
        }
        [self reloadAll];
    }];
    [self.navigationController pushViewController:b animated:YES];
}

- (void)promptNewProjectWithTemplate:(NSString *)tpl {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建工程"
        message:( [tpl isEqualToString:@"tweak"] ? @"一个最小可编译的 tweak（hook SpringBoard）" : @"一个最小可运行的空 App")
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"工程名（英文，如 MyTweak）";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"包标识";
        tf.text = @"com.example.";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *name = a.textFields[0].text;
        NSString *bundle = a.textFields[1].text;
        if (!name.length) return;
        NSError *err = nil;
        NSString *path = [self createProjectTemplate:tpl name:name bundleId:bundle error:&err];
        if (!path) {
            [self presentAlert:@"创建失败" message:err.localizedDescription ?: @"同名工程可能已存在"];
            return;
        }
        [SPMotion hapticSuccess];
        SPProject *p = [SPProject projectAtPath:path error:NULL];
        // 新建项目套用「设置 → 编译默认值 + 混淆」
        p.options = [[SPStore shared] optionsForProjectPath:@"__defaults__"];
        [[SPStore shared] saveOptions:p.options forProjectPath:p.path];
        [[SPStore shared] pushRecentProject:p];
        [self reloadAll];
        SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSString *)createProjectTemplate:(NSString *)tpl name:(NSString *)name bundleId:(NSString *)bundleId error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [SPStore shared].projectsDirectory;
    NSString *path = [root stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:path]) {
        if (error) *error = SPError(SPErrorCodeIO, @"同名工程已存在");
        return nil;
    }
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    BOOL isApp = [tpl isEqualToString:@"application"];
    NSString *identifier = bundleId.length && ![bundleId isEqualToString:@"com.example."]
        ? bundleId : [@"com.example." stringByAppendingString:name.lowercaseString];

    NSString *makefile = isApp
        ? [NSString stringWithFormat:@"TARGET = iphone:clang:latest:15.0\n"
                                     "ARCHS = arm64 arm64e\n\n"
                                     "include $(THEOS)/makefiles/common.mk\n\n"
                                     "APPLICATION_NAME = %@\n\n"
                                     "%@_FILES = main.m RootViewController.m\n"
                                     "%@_FRAMEWORKS = UIKit Foundation\n\n"
                                     "include $(THEOS_MAKE_PATH)/application.mk\n", name, name, name, name]
        : [NSString stringWithFormat:@"TARGET = iphone:clang:latest:15.0\n"
                                     "ARCHS = arm64 arm64e\n"
                                     "INSTALL_TARGET_PROCESSES = SpringBoard\n\n"
                                     "include $(THEOS)/makefiles/common.mk\n\n"
                                     "TWEAK_NAME = %@\n\n"
                                     "%@_FILES = Tweak.x\n"
                                     "%@_CFLAGS = -fobjc-arc\n\n"
                                     "include $(THEOS_MAKE_PATH)/tweak.mk\n", name, name, name];
    [makefile writeToFile:[path stringByAppendingPathComponent:@"Makefile"] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL];

    NSString *control = [NSString stringWithFormat:
        @"Package: %@\nName: %@\nVersion: 1.0.0\nArchitecture: iphoneos-arm\n"
         "Description: 由 Spark 创建\nMaintainer: Spark\nAuthor: Spark\nSection: %@\n",
        identifier, name, isApp ? @"Applications" : @"Tweaks"];
    [control writeToFile:[path stringByAppendingPathComponent:@"control"] atomically:YES
                encoding:NSUTF8StringEncoding error:NULL];

    if (isApp) {
        [@"#import <UIKit/UIKit.h>\n#import \"RootViewController.h\"\n\n"
          "@interface AppDelegate : UIResponder <UIApplicationDelegate>\n"
          "@property (nonatomic, strong) UIWindow *window;\n@end\n\n"
          "@implementation AppDelegate\n"
          "- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {\n"
          "    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];\n"
          "    self.window.rootViewController = [RootViewController new];\n"
          "    [self.window makeKeyAndVisible];\n    return YES;\n}\n@end\n\n"
          "int main(int argc, char *argv[]) {\n    @autoreleasepool {\n"
          "        return UIApplicationMain(argc, argv, nil, @\"AppDelegate\");\n    }\n}\n"
         writeToFile:[path stringByAppendingPathComponent:@"main.m"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
        [@"#import <UIKit/UIKit.h>\n\n@interface RootViewController : UIViewController\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"RootViewController.h"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
        [@"#import \"RootViewController.h\"\n\n@implementation RootViewController\n\n"
          "- (void)viewDidLoad {\n    [super viewDidLoad];\n"
          "    self.title = @\"Hello\";\n"
          "    self.view.backgroundColor = [UIColor systemBackgroundColor];\n\n"
          "    UILabel *label = [[UILabel alloc] init];\n"
          "    label.text = @\"Hello Spark\";\n"
          "    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];\n"
          "    label.translatesAutoresizingMaskIntoConstraints = NO;\n"
          "    [self.view addSubview:label];\n"
          "    [NSLayoutConstraint activateConstraints:@[\n"
          "        [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],\n"
          "        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],\n"
          "    ]];\n}\n\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"RootViewController.m"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
    } else {
        [@"// Spark 生成的 tweak：最简单的 SpringBoard hook\n%hook SpringBoard\n\n"
          "- (void)applicationDidFinishLaunching:(id)application {\n"
          "    %orig;\n    NSLog(@\"[%@] loaded\");\n}\n\n%end\n"
         writeToFile:[path stringByAppendingPathComponent:@"Tweak.x"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
    }

    [fm createDirectoryAtPath:[path stringByAppendingPathComponent:@"layout/DEBIAN"]
  withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"*.deb\npackages/\n.theos/\n_build/\n*.dSYM/\nobj/\n.sparkbak/\n"
     writeToFile:[path stringByAppendingPathComponent:@".gitignore"] atomically:YES
        encoding:NSUTF8StringEncoding error:NULL];
    return path;
}

#pragma mark - 工具

- (void)presentAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
