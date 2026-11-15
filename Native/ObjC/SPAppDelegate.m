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
#import "SPStore.h"
#import "SPToolchain.h"
#import "SPCompat.h"

@interface SPAppDelegate ()
@property (nonatomic, strong) UITabBarController *tabs;
@end

@implementation SPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    [self configureAppearance];
    [self setupDefaults];

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

    // 1. 项目
    SPProjectsViewController *projects = [[SPProjectsViewController alloc] init];
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:projects];
    nav1.tabBarItem = [self tabItem:@"项目" symbol:@"hammer" selected:@"hammer.fill"];

    // 2. 工具链
    SPToolchainViewController *tools = [[SPToolchainViewController alloc] init];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:tools];
    nav2.tabBarItem = [self tabItem:@"工具链" symbol:@"cpu" selected:@"cpu.fill"];

    // 3. 逆向
    SPReverseViewController *rev = [[SPReverseViewController alloc] initWithBinaryPath:nil profile:nil];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:rev];
    nav3.tabBarItem = [self tabItem:@"逆向" symbol:@"binoculars" selected:@"binoculars.fill"];

    // 4. 注入
    SPTrollViewController *troll = [[SPTrollViewController alloc] init];
    UINavigationController *nav4 = [[UINavigationController alloc] initWithRootViewController:troll];
    nav4.tabBarItem = [self tabItem:@"注入" symbol:@"syringe" selected:@"syringe.fill"];

    self.tabs.viewControllers = @[nav1, nav2, nav3, nav4];
    self.tabs.selectedIndex = 0;
}

/// HIG：SF Symbols + 稳定标题，iOS 15 起用 UITabBarItem 的 image/selectedImage
- (UITabBarItem *)tabItem:(NSString *)title symbol:(NSString *)symbol selected:(NSString *)selected {
    UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:nil selectedImage:nil];
    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:symbol];
        UIImage *sel = [UIImage systemImageNamed:selected];
        item.image = img;
        item.selectedImage = sel;
    }
    return item;
}

- (void)showWelcome {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"欢迎使用 Spark"
                         message:@"参考 Rein 的可视化编译工具：\n"
                                 @"• 一键编译 Theos / Logos 工程\n"
                                 @"• OLLVM 混淆与逆向工具\n"
                                 @"• 巨魔（TrollStore）注入\n\n"
                                 @"先从「工具链」页确认环境，再回「项目」页新建或导入工程。"
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
        NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *item in c.queryItems) {
            if ([item.name isEqualToString:@"path"] && item.value.length) {
                [self openProjectAtPath:item.value];
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - 生命周期

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [SPSettings.shared save];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
