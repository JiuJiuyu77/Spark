//
//  SPAppDelegate.m
//

#import "SPAppDelegate.h"
#import "SPTheme.h"
#import "SPProjectsViewController.h"
#import "SPToolchainViewController.h"
#import "SPReverseViewController.h"
#import "SPTrollViewController.h"
#import "SPStore.h"
#import "SPToolchain.h"
#import "SPCompat.h"
#import "SPProjectViewController.h"

@interface SPAppDelegate ()
@property (nonatomic, strong) UITabBarController *tabs;
@end

@implementation SPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    // 全局外观
    [self configureAppearance];

    // 启动即扫一遍工具链（后台）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[SPToolchain shared] rescan];
    });

    [self buildTabBar];

    // 处理「从文件 App 打开」的情况：Spark 会作为文件夹的「打开方式」出现
    // （Info.plist 里注册了 public.folder）
    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
        if (url.isFileURL) [self openProjectAtPath:url.path];
    }

    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)configureAppearance {
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithOpaqueBackground];
    nav.backgroundColor = [SPTheme background];
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: [SPTheme text],
                                NSFontAttributeName: [SPTheme uiFont:17 weight:UIFontWeightSemibold]};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [SPTheme text],
                                     NSFontAttributeName: [SPTheme uiFont:30 weight:UIFontWeightBold]};
    nav.shadowColor = [SPTheme separator];
    [UINavigationBar appearance].standardAppearance = nav;
    [UINavigationBar appearance].scrollEdgeAppearance = nav;
    [UINavigationBar appearance].compactAppearance = nav;
    [UINavigationBar appearance].tintColor = [SPTheme accent];

    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithOpaqueBackground];
    tab.backgroundColor = [SPTheme surface];
    tab.shadowColor = [SPTheme separator];
    [UITabBar appearance].standardAppearance = tab;
    [UITabBar appearance].scrollEdgeAppearance = tab;
    [UITabBar appearance].tintColor = [SPTheme accent];
}

- (void)buildTabBar {
    self.tabs = [[UITabBarController alloc] init];

    SPProjectsViewController *projects = [[SPProjectsViewController alloc] init];
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:projects];
    nav1.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"项目"
                                                    image:[UIImage systemImageNamed:@"hammer.fill"]
                                            selectedImage:[UIImage systemImageNamed:@"hammer.fill"]];

    SPToolchainViewController *tools = [[SPToolchainViewController alloc] init];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:tools];
    nav2.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"工具链"
                                                    image:[UIImage systemImageNamed:@"cpu"]
                                            selectedImage:[UIImage systemImageNamed:@"cpu.fill"]];

    SPReverseViewController *rev = [[SPReverseViewController alloc] initWithBinaryPath:nil profile:nil];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:rev];
    nav3.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"逆向"
                                                    image:[UIImage systemImageNamed:@"binoculars.fill"]
                                            selectedImage:[UIImage systemImageNamed:@"binoculars.fill"]];

    // 巨魔注入器：参考 TrollFools 的注入流程，作为第四个标签
    SPTrollViewController *troll = [[SPTrollViewController alloc] init];
    UINavigationController *nav4 = [[UINavigationController alloc] initWithRootViewController:troll];
    nav4.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"注入"
                                                    image:[UIImage systemImageNamed:@"syringe.fill"]
                                            selectedImage:[UIImage systemImageNamed:@"syringe.fill"]];

    self.tabs.viewControllers = @[nav1, nav2, nav3, nav4];
    self.tabs.selectedIndex = 0;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openToolchainTab)
                                                 name:SPOpenToolchainTabNotification object:nil];
}

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

#pragma mark - 打开 URL

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    // spark://build?path=/var/mobile/xxx  直接编译某个项目
    if ([url.scheme isEqualToString:@"spark"]) {
        NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *path = nil;
        for (NSURLQueryItem *item in c.queryItems) if ([item.name isEqualToString:@"path"]) path = item.value;
        if (path.length) {
            [self openProjectAtPath:path];
            return YES;
        }
    }
    if (url.isFileURL && [url.pathExtension isEqualToString:@"deb"]) {
        // 打开 deb：跳到产物预览（这里只提示，安装交给 Filza）
    }
    return NO;
}

#pragma mark - 生命周期

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [[SPSettings shared] save];
}

@end
