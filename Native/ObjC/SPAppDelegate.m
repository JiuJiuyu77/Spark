//
//  SPAppDelegate.m
//

#import "SPAppDelegate.h"
#import "SPTheme.h"
#import "SPProjectsViewController.h"
#import "SPToolchainViewController.h"
#import "SPReverseViewController.h"
#import "SPTrollViewController.h"
#import "SPProjectViewController.h"
#import "SPSettingsViewController.h"
#import "SPMeViewController.h"
#import "SPIncoming.h"
#import "SPInboxViewController.h"
#import "SPSession.h"
#import "SPToolsViewController.h"
#import "SPGlassKit.h"
#import "SPJIT.h"
#import "SPCrashGuard.h"
#import "SPPrivileged.h"
#import "SPEditorViewController.h"
#import "SPToolchainInstaller.h"
#import "SPStore.h"
#import "SPToolchain.h"
#import "SPCompat.h"

@interface SPAppDelegate () <SPFloatTabBarDelegate>
@property (nonatomic, strong) UITabBarController *tabs;
@property (nonatomic, strong) SPFloatTabBar *floatBar;
@end

@implementation SPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    // 第一件事：尝试提权到 root（TrollStore 环境下通常直接成功）
    // 必须在任何子进程启动之前做，否则子进程会继承 mobile 身份
    BOOL isRoot = [[SPPrivileged shared] elevateSelf];
    SPLog(@"启动身份：uid=%d gid=%d root=%@", (int)getuid(), (int)getgid(), isRoot ? @"是" : @"否");

    // 崩溃兜底：尽早装，才能捕获启动期异常
    [[SPCrashGuard shared] install];

    [self configureAppearance];
    [self setupDefaults];

    // JIT：后台探测一次，结果在「设置 → 显示与反馈」里看
    [[SPJIT shared] startServiceIfNeeded];

    // 启动时后台扫一遍工具链，别阻塞首屏
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[SPToolchain shared] rescan];
    });

    [self buildTabBar];

    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
        if (url.isFileURL) [self openProjectAtPath:url.path];
    }

    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];

    // 启动时收编 Share Extension 留下的文件（不打断用户）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[SPIncoming shared] drainSharedIncoming];
    });

    // 内置工具链：首启后台静默展开（约 480MB，一分钟内），完成后自动重扫
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    if (inst.hasBundledToolchain && !inst.isInstalled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [inst installWithProgress:nil completion:^(BOOL ok, NSError *err) {
                if (ok) {
                    [[SPToolchain shared] rescan];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SPToolchainInstalled" object:nil];
                }
            }];
        });
    }

    // 上次异常退出？提示一次（不打扰、可忽略）
    NSString *crashReport = [[SPCrashGuard shared] pendingReportPath];
    if (crashReport.length) {
        [[SPCrashGuard shared] consumePendingReport];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"上次意外退出"
                message:@"Spark 检测到上次是异常退出的，已保存崩溃报告。要看吗？"
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"查看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:crashReport];
                UINavigationController *nav = self.tabs.viewControllers.lastObject;
                [nav pushViewController:e animated:YES];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"忽略" style:UIAlertActionStyleCancel handler:nil]];
            [self.tabs presentViewController:a animated:YES completion:nil];
        });
    }

    // 首次启动的「一句话说明」，别让用户面对空列表发懵
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"Spark.onboarded"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Spark.onboarded"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showWelcome];
        });
    }
    return YES;
}

#pragma mark - 外观（Apple HIG）

- (void)configureAppearance {
    // 导航栏：跟随系统（不强行染成黑色），大标题靠 InsetGrouped 列表衬出来
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithDefaultBackground];
    nav.titleTextAttributes = @{NSFontAttributeName: [SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold]};
    nav.largeTitleTextAttributes = @{NSFontAttributeName: [SPTheme scaled:UIFontTextStyleLargeTitle weight:UIFontWeightBold]};
    [UINavigationBar appearance].standardAppearance = nav;
    [UINavigationBar appearance].scrollEdgeAppearance = nav;
    [UINavigationBar appearance].compactAppearance = nav;
    [UINavigationBar appearance].tintColor = [SPTheme accent];

    // 标签栏：系统默认即可，只统一 tint
    [UITabBar appearance].tintColor = [SPTheme accent];

    // 列表：分组背景 + 不显示多余分隔线
    UITableView.appearance.backgroundColor = [SPTheme background];
    UITableViewCell.appearance.backgroundColor = [SPTheme surface];
    UITableViewCell.appearance.textLabel.textColor = nil;
}

- (void)setupDefaults {
    // 触感反馈默认开启（用户可在「工具链 → 日志/显示」里关）
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:@"Spark.haptics"] == nil) [d setBool:YES forKey:@"Spark.haptics"];
}

#pragma mark - 标签页

- (void)buildTabBar {
    self.tabs = [[UITabBarController alloc] init];
    self.tabs.tabBar.hidden = YES;   // 用悬浮玻璃栏替代系统 tab bar

    SPProjectsViewController *projects = [[SPProjectsViewController alloc] init];
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:projects];

    SPToolsViewController *tools = [[SPToolsViewController alloc] init];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:tools];

    SPMeViewController *me = [[SPMeViewController alloc] init];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:me];

    self.tabs.viewControllers = @[nav1, nav2, nav3];

    self.floatBar = [[SPFloatTabBar alloc] initWithTitles:@[@"项目", @"工具", @"我的"]
                                                  symbols:@[@"square.grid.2x2", @"wrench.and.screwdriver", @"person.crop.circle"]
                                          selectedSymbols:@[@"square.grid.2x2.fill", @"wrench.and.screwdriver.fill", @"person.crop.circle.fill"]];
    self.floatBar.delegate = self;
    self.floatBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.floatBar.selectedIndex = 0;

    // 为什么挂在 tabs.view 而不是 window：
    //   1. window 上直接加子视图会被 UITabBarController 的根视图压住
    //   2. window.safeAreaLayoutGuide 在 buildTabBar 时就取值是 0，
    //      底栏会被顶到屏幕外面（表现就是「底栏不见了」）
    // 挂到 tabs.view 上用 safeArea 约束，布局时机与系统一致。
    [self.tabs.view addSubview:self.floatBar];
    UILayoutGuide *safe = self.tabs.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.floatBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:SPFloatingBarSideInset],
        [self.floatBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-SPFloatingBarSideInset],
        [self.floatBar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-SPSpaceXS],
    ]];

    // 让内容底部留出悬浮栏的高度，避免最后一行被挡住
    self.tabs.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, SPFloatingBarInset, 0);
}

#pragma mark - SPFloatTabBarDelegate

- (void)floatTabBar:(SPFloatTabBar *)bar didSelectIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.viewControllers.count) return;
    self.tabs.selectedIndex = index;
}



- (void)showWelcome {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"欢迎使用 Spark"
                         message:@"参考 Rein 的可视化编译工具：\n"
                                 @"• 一键编译 Theos / Logos 工程\n"
                                 @"• OLLVM 混淆与逆向工具\n"
                                 @"• 巨魔（TrollStore）注入\n\n"
                                 @"内置编译工具链会在首次启动时自动展开；SDK 需要你在「设置 → 工具链」里导入。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"去检查工具链" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.tabs.selectedIndex = 1;
    }]];
    [self.tabs presentViewController:a animated:YES completion:nil];
}

#pragma mark - 跳转

- (void)openToolchainTab {
    self.tabs.selectedIndex = 1;
}

- (void)openProjectAtPath:(NSString *)path {
    SPProject *p = [SPProject projectAtPath:path error:NULL];
    if (!p) return;
    p.options = [[SPStore shared] optionsForProjectPath:p.path];
    [[SPStore shared] pushRecentProject:p];
    UINavigationController *nav = self.tabs.viewControllers.firstObject;
    SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
    [nav pushViewController:vc animated:NO];
}

#pragma mark - URL

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if ([url.scheme isEqualToString:@"spark"]) {
        // spark://import —— Share Extension 拉活，收编它写进共享容器的文件
        if ([url.host isEqualToString:@"import"]) {
            NSArray *items = [[SPIncoming shared] drainSharedIncoming];
            [self showInbox];
            if (items.count) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已收到文件"
                        message:[NSString stringWithFormat:@"共 %lu 个，可在收件箱里导入为项目。", (unsigned long)items.count]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [self.tabs presentViewController:a animated:YES completion:nil];
                });
            }
            return YES;
        }
        NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *item in c.queryItems) {
            if ([item.name isEqualToString:@"path"] && item.value.length) {
                [self openProjectAtPath:item.value];
                return YES;
            }
        }
    }
    // 「用 Spark 打开」传来的文件
    if (url.isFileURL) {
        NSURL *copy = url;
        if ([copy startAccessingSecurityScopedResource]) {
            [[SPIncoming shared] importPath:copy.path error:NULL];
            [copy stopAccessingSecurityScopedResource];
        } else {
            [[SPIncoming shared] importPath:copy.path error:NULL];
        }
        [self showInbox];
        return YES;
    }
    return NO;
}

/// 切到「我的」并打开收件箱
- (void)showInbox {
    self.tabs.selectedIndex = 2;
    self.floatBar.selectedIndex = 2;
    UINavigationController *nav = self.tabs.viewControllers.lastObject;
    [nav popToRootViewControllerAnimated:NO];
    SPInboxViewController *vc = [[SPInboxViewController alloc] init];
    [nav pushViewController:vc animated:YES];
}

#pragma mark - 生命周期

- (void)applicationWillTerminate:(UIApplication *)application {
    // 父进程要走了：把 make/clang 一起收掉，避免留下孤儿进程（Rein boot.js 的做法）
    SPSessionReapAllChildren();
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [SPSettings.shared save];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
