//
//  RBAppDelegate.m
//

#import "RBAppDelegate.h"
#import "RBTheme.h"
#import "RBProjectsViewController.h"
#import "RBToolchainViewController.h"
#import "RBReverseViewController.h"
#import "RBStore.h"
#import "RBToolchain.h"
#import "RBCompat.h"
#import "RBProjectViewController.h"

@interface RBAppDelegate ()
@property (nonatomic, strong) UITabBarController *tabs;
@end

@implementation RBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    // 全局外观
    [self configureAppearance];

    // 启动即扫一遍工具链（后台）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[RBToolchain shared] rescan];
    });

    [self buildTabBar];

    // 处理「从文件 App 打开」的情况：ReinBuild 会作为文件夹的「打开方式」出现
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
    nav.backgroundColor = [RBTheme background];
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: [RBTheme text],
                                NSFontAttributeName: [RBTheme uiFont:17 weight:UIFontWeightSemibold]};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [RBTheme text],
                                     NSFontAttributeName: [RBTheme uiFont:30 weight:UIFontWeightBold]};
    nav.shadowColor = [RBTheme separator];
    [UINavigationBar appearance].standardAppearance = nav;
    [UINavigationBar appearance].scrollEdgeAppearance = nav;
    [UINavigationBar appearance].compactAppearance = nav;
    [UINavigationBar appearance].tintColor = [RBTheme accent];

    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithOpaqueBackground];
    tab.backgroundColor = [RBTheme surface];
    tab.shadowColor = [RBTheme separator];
    [UITabBar appearance].standardAppearance = tab;
    [UITabBar appearance].scrollEdgeAppearance = tab;
    [UITabBar appearance].tintColor = [RBTheme accent];
}

- (void)buildTabBar {
    self.tabs = [[UITabBarController alloc] init];

    RBProjectsViewController *projects = [[RBProjectsViewController alloc] init];
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:projects];
    nav1.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"项目"
                                                    image:[UIImage systemImageNamed:@"hammer.fill"]
                                            selectedImage:[UIImage systemImageNamed:@"hammer.fill"]];

    RBToolchainViewController *tools = [[RBToolchainViewController alloc] init];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:tools];
    nav2.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"工具链"
                                                    image:[UIImage systemImageNamed:@"cpu"]
                                            selectedImage:[UIImage systemImageNamed:@"cpu.fill"]];

    RBReverseViewController *rev = [[RBReverseViewController alloc] initWithBinaryPath:nil profile:nil];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:rev];
    nav3.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"逆向"
                                                    image:[UIImage systemImageNamed:@"binoculars.fill"]
                                            selectedImage:[UIImage systemImageNamed:@"binoculars.fill"]];

    self.tabs.viewControllers = @[nav1, nav2, nav3];
    self.tabs.selectedIndex = 0;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openToolchainTab)
                                                 name:RBOpenToolchainTabNotification object:nil];
}

- (void)openToolchainTab {
    self.tabs.selectedIndex = 1;
}

- (void)openProjectAtPath:(NSString *)path {
    RBProject *p = [RBProject projectAtPath:path error:NULL];
    if (!p) return;
    p.options = [[RBStore shared] optionsForProjectPath:p.path];
    [[RBStore shared] pushRecentProject:p];
    UINavigationController *nav = self.tabs.viewControllers.firstObject;
    RBProjectViewController *vc = [[RBProjectViewController alloc] initWithProject:p];
    [nav pushViewController:vc animated:NO];
}

#pragma mark - 打开 URL

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    // reinbuild://build?path=/var/mobile/xxx  直接编译某个项目
    if ([url.scheme isEqualToString:@"reinbuild"]) {
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
    [[RBSettings shared] save];
}

@end
