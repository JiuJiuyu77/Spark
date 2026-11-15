//
//  SPProjectsViewController.m
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

NSString *const SPOpenToolchainTabNotification = @"SPOpenToolchainTab";
NSString *const SPProjectCreatedNotification = @"SPProjectCreated";

@interface SPProjectsViewController () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) UIView *emptyView;
@end

@implementation SPProjectsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"Spark";
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    self.table.rowHeight = 64;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"p"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索项目";
    self.navigationItem.searchController = self.search;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(addTapped)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"扫描" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(scanTapped)];

    [self reloadAll];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadAll)
                                                 name:SPProjectCreatedNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - 数据

- (void)reloadAll {
    NSMutableArray *all = [NSMutableArray arrayWithArray:[[SPStore shared] recentProjects]];

    // 把 projectsRoot 下的目录也当项目列出来（去重）
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

    if (self.filter.length) {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
            return [d[@"name"] localizedCaseInsensitiveContainsString:self.filter];
        }];
        all = [[all filteredArrayUsingPredicate:p] mutableCopy];
    }
    self.items = all;
    [self.table reloadData];
    [self updateEmptyState];

    [[SPToolchain shared] rescan];
    self.navigationItem.prompt = [NSString stringWithFormat:@"%@ │ 长按项目可删除",
                                  [[SPToolchain shared].scan summary]];
}

- (void)updateEmptyState {
    if (self.items.count) { self.table.backgroundView = nil; return; }
    UIView *v = [[UIView alloc] init];
    UILabel *l = [[UILabel alloc] init];
    l.text = @"还没有项目\n点右上角 + 新建，或从 Rein 目录导入";
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [SPTheme uiFont:14 weight:UIFontWeightRegular];
    l.textColor = [SPTheme textDim];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [l.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-60],
    ]];
    self.table.backgroundView = v;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.filter = sc.searchBar.text ?: @"";
    [self reloadAll];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.items.count ? @"项目" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"p"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"p"];
    NSDictionary *d = self.items[ip.row];
    cell.backgroundColor = [SPTheme surface];
    cell.textLabel.text = d[@"name"] ?: @"";
    cell.textLabel.textColor = [SPTheme text];
    cell.textLabel.font = [SPTheme uiFont:15 weight:UIFontWeightSemibold];

    NSString *kind = d[@"kind"] ?: @"";
    NSString *summary = d[@"summary"] ?: @"";
    NSString *path = [d[@"path"] stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@  %@", kind, summary, path];
    cell.detailTextLabel.textColor = [SPTheme textDim];
    cell.detailTextLabel.font = [SPTheme monoFont:10];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    for (UIGestureRecognizer *g in [cell.contentView.gestureRecognizers copy]) {
        if ([g isKindOfClass:UILongPressGestureRecognizer.class]) [cell.contentView removeGestureRecognizer:g];
    }
    [cell.contentView addGestureRecognizer:lp];
    return cell;
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIView *v = g.view;
    while (v && ![v isKindOfClass:UITableViewCell.class]) v = v.superview;
    NSIndexPath *ip = [self.table indexPathForCell:(UITableViewCell *)v];
    if (!ip) return;
    NSDictionary *d = self.items[ip.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:d[@"name"] message:d[@"path"]
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从列表移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[SPStore shared] removeRecentProjectAtPath:d[@"path"]];
        [self reloadAll];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = d[@"path"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = v;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *d = self.items[ip.row];
    NSError *err = nil;
    SPProject *p = [SPProject projectAtPath:d[@"path"] error:&err];
    if (!p) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"打不开" message:err.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    p.options = [[SPStore shared] optionsForProjectPath:p.path];
    [[SPStore shared] pushRecentProject:p];
    SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 新建 / 扫描

- (void)addTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"新建 / 导入"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Theos Tweak 模板" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptNewProjectWithTemplate:@"tweak"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Application 模板" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptNewProjectWithTemplate:@"application"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从磁盘选择目录（导入）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pickDirectory];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从 Rein 目录扫描" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *root = [[SPToolchain shared] reinRoot];
        [self scanRoot:root];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)scanTapped {
    NSString *root = [SPStore shared].projectsDirectory;
    [self scanRoot:root];
}

- (void)scanRoot:(NSString *)root {
    SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:root
                                                                              pickMode:NO
                                                                           fileFilters:nil
                                                                                onPick:nil];
    b.title = @"扫描项目";
    [self.navigationController pushViewController:b animated:YES];
}

- (void)pickDirectory {
    SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:NSHomeDirectory()
                                                                              pickMode:YES
                                                                           fileFilters:nil
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
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建项目"
        message:[NSString stringWithFormat:@"模板：%@", tpl] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"项目名（英文，例如 MyTweak）";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"包标识（com.example.mytweak）";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.text = @"com.example.";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *name = a.textFields[0].text;
        NSString *bundle = a.textFields[1].text;
        if (!name.length) return;
        NSError *err = nil;
        NSString *path = [self createProjectTemplate:tpl name:name bundleId:bundle error:&err];
        if (!path) {
            UIAlertController *e = [UIAlertController alertControllerWithTitle:@"创建失败"
                message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:e animated:YES completion:nil];
            return;
        }
        SPProject *p = [SPProject projectAtPath:path error:NULL];
        p.options = [[SPStore shared] optionsForProjectPath:p.path];
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
        if (error) *error = SPError(SPErrorCodeIO, @"同名项目已存在");
        return nil;
    }
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    BOOL isApp = [tpl isEqualToString:@"application"];
    NSString *makefile = isApp
        ? [NSString stringWithFormat:@"TARGET = iphone:clang:latest:15.0\n"
                                     "ARCHS = arm64 arm64e\n"
                                     "INSTALL_TARGET_PROCESSES = %@\n\n"
                                     "include $(THEOS)/makefiles/common.mk\n\n"
                                     "APPLICATION_NAME = %@\n\n"
                                     "%@_FILES = main.m RootViewController.m\n"
                                     "%@_FRAMEWORKS = UIKit Foundation\n"
                                     "%@_CODESIGN_FLAGS = -Ssign.plist\n\n"
                                     "include $(THEOS_MAKE_PATH)/application.mk\n", name, name, name, name, name]
        : [NSString stringWithFormat:@"TARGET = iphone:clang:latest:15.0\n"
                                     "ARCHS = arm64 arm64e\n"
                                     "INSTALL_TARGET_PROCESSES = SpringBoard\n\n"
                                     "include $(THEOS)/makefiles/common.mk\n\n"
                                     "TWEAK_NAME = %@\n\n"
                                     "%@_FILES = Tweak.x\n"
                                     "%@_CFLAGS = -fobjc-arc\n\n"
                                     "include $(THEOS_MAKE_PATH)/tweak.mk\n", name, name, name];
    [makefile writeToFile:[path stringByAppendingPathComponent:@"Makefile"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSString *control = [NSString stringWithFormat:@"Package: %@\nName: %@\nVersion: 1.0.0\n"
                         "Architecture: iphoneos-arm\nDescription: 由 Spark 创建\n"
                         "Maintainer: Spark\nAuthor: Spark\nSection: Tweaks\n",
                         bundleId.length ? bundleId : [@"com.example." stringByAppendingString:name.lowercaseString], name];
    [control writeToFile:[path stringByAppendingPathComponent:@"control"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    if (isApp) {
        [@"#import <UIKit/UIKit.h>\n#import \"RootViewController.h\"\n\n"
          "int main(int argc, char *argv[]) {\n"
          "    @autoreleasepool {\n"
          "        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));\n"
          "    }\n}\n"
         writeToFile:[path stringByAppendingPathComponent:@"main.m"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"#import <UIKit/UIKit.h>\n\n@interface AppDelegate : UIResponder <UIApplicationDelegate>\n"
          "@property (nonatomic, strong) UIWindow *window;\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"AppDelegate.h"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"#import \"AppDelegate.h\"\n#import \"RootViewController.h\"\n\n"
          "@implementation AppDelegate\n"
          "- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {\n"
          "    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];\n"
          "    self.window.rootViewController = [RootViewController new];\n"
          "    [self.window makeKeyAndVisible];\n"
          "    return YES;\n}\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"AppDelegate.m"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"#import <UIKit/UIKit.h>\n\n@interface RootViewController : UIViewController\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"RootViewController.h"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"#import \"RootViewController.h\"\n\n@implementation RootViewController\n"
          "- (void)viewDidLoad {\n    [super viewDidLoad];\n"
          "    self.view.backgroundColor = [UIColor systemBackgroundColor];\n"
          "    UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];\n"
          "    label.text = @\"Hello Spark\";\n    label.textAlignment = NSTextAlignmentCenter;\n"
          "    [self.view addSubview:label];\n}\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"RootViewController.m"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    } else {
        [@"// 由 Spark 生成\n%hook SpringBoard\n\n"
          "- (void)applicationDidFinishLaunching:(id)application {\n"
          "    %orig;\n    NSLog(@\"[Spark] tweak loaded\");\n}\n\n"
          "%end\n"
         writeToFile:[path stringByAppendingPathComponent:@"Tweak.x"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *entry = [path stringByAppendingPathComponent:@"Resources"];
        [fm createDirectoryAtPath:entry withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    [fm createDirectoryAtPath:[path stringByAppendingPathComponent:@"layout/DEBIAN"] withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *gitignore = @"*.deb\npackages/\n.theos/\n_build/\n*.dSYM/\nobj/\n";
    [gitignore writeToFile:[path stringByAppendingPathComponent:@".gitignore"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    return path;
}

@end
