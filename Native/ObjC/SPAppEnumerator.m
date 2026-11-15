//
//  SPAppEnumerator.m
//

#import "SPAppEnumerator.h"
#import "SPCompat.h"
#import <objc/message.h>

// 文件系统回退时扫这两处
static NSString *const kBundleRoot = @"/private/var/containers/Bundle/Application";
static NSString *const kSystemApps = @"/Applications";

@interface SPAppEnumerator ()
@property (nonatomic, assign) BOOL usedLaunchServices;
@property (nonatomic, assign) NSTimeInterval lastEnumerationSeconds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *iconCache;
@end

@implementation SPAppInfo
@end

@implementation SPAppEnumerator

+ (instancetype)shared {
    static SPAppEnumerator *e;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        e = [SPAppEnumerator new];
        e.iconCache = [NSMutableDictionary dictionary];
    });
    return e;
}

#pragma mark - 枚举

- (NSArray<SPAppInfo *> *)allApps {
    NSDate *t0 = [NSDate date];

    NSArray *apps = [self appsFromLaunchServices];
    if (apps.count) {
        self.usedLaunchServices = YES;
    } else {
        self.usedLaunchServices = NO;
        apps = [self appsFromFileSystem];
    }

    self.lastEnumerationSeconds = -[t0 timeIntervalSinceNow];
    SPLog(@"枚举 App：%lu 个（LaunchServices=%@，耗时 %.0fms）",
          (unsigned long)apps.count, self.usedLaunchServices ? @"是" : @"否",
          self.lastEnumerationSeconds * 1000);
    return apps;
}

- (NSArray<SPAppInfo *> *)appsFromLaunchServices {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return @[];

    id workspace = nil;
    if ([workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, @selector(defaultWorkspace));
    }
    if (!workspace) return @[];

    SEL allSel = @selector(allInstalledApplications);
    if (![workspace respondsToSelector:allSel]) return @[];

    NSArray *proxies = ((id (*)(id, SEL))objc_msgSend)(workspace, allSel);
    if (![proxies isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<SPAppInfo *> *out = [NSMutableArray array];
    for (id proxy in proxies) {
        SPAppInfo *info = [self infoFromProxy:proxy];
        if (info && info.bundleId.length) [out addObject:info];
    }

    // 稳定排序：Spark 自己排最前，其余按显示名
    [out sortUsingComparator:^NSComparisonResult(SPAppInfo *a, SPAppInfo *b) {
        if ([a.bundleId isEqualToString:@"com.HuQing.Spark"]) return NSOrderedAscending;
        if ([b.bundleId isEqualToString:@"com.HuQing.Spark"]) return NSOrderedDescending;
        return [a.displayName localizedStandardCompare:b.displayName];
    }];
    return out;
}

/// 从 LSApplicationProxy 取我们要的字段（全部用反射，不依赖私有头文件）
- (nullable SPAppInfo *)infoFromProxy:(id)proxy {
    if (!proxy) return nil;

    NSString *(^str)(SEL) = ^NSString *(SEL sel) {
        if (![proxy respondsToSelector:sel]) return nil;
        id v = ((id (*)(id, SEL))objc_msgSend)(proxy, sel);
        return [v isKindOfClass:[NSString class]] ? v : nil;
    };
    NSString *bundleId = str(@selector(applicationIdentifier));
    if (!bundleId.length) return nil;

    SPAppInfo *a = [SPAppInfo new];
    a.bundleId = bundleId;
    a.isFromLaunchServices = YES;

    NSString *name = str(@selector(localizedName));
    if (!name.length) name = str(@selector(itemName));
    if (!name.length) name = bundleId;
    a.displayName = name;

    a.version = str(@selector(shortVersionString)) ?: str(@selector(bundleVersion)) ?: @"";
    a.executable = str(@selector(bundleExecutable)) ?: @"";

    // 路径：bundleURL / dataContainerURL 都是 NSURL
    SEL urlSel = NSSelectorFromString(@"bundleURL");
    if ([proxy respondsToSelector:urlSel]) {
        NSURL *u = ((id (*)(id, SEL))objc_msgSend)(proxy, urlSel);
        if ([u isKindOfClass:[NSURL class]]) a.appPath = u.path;
    }
    SEL dataSel = NSSelectorFromString(@"dataContainerURL");
    if ([proxy respondsToSelector:dataSel]) {
        NSURL *u = ((id (*)(id, SEL))objc_msgSend)(proxy, dataSel);
        if ([u isKindOfClass:[NSURL class]]) a.dataContainer = u.path;
    }

    // 系统 App：bundle 路径在 /Applications 或 /System 下
    if (!a.appPath.length) {
        SEL pathSel = NSSelectorFromString(@"bundleURL");
        (void)pathSel;
    }
    NSString *p = a.appPath ?: @"";
    a.isSystem = [p hasPrefix:@"/Applications/"] || [p hasPrefix:@"/System/"];

    if (!a.executable.length) a.executable = a.appPath.lastPathComponent.stringByDeletingPathExtension;
    return a;
}

- (NSArray<SPAppInfo *> *)appsFromFileSystem {
    NSMutableArray<SPAppInfo *> *list = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    // 1) 用户装的 App：.../Bundle/Application/<UUID>/Xxx.app
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:kBundleRoot error:NULL] ?: @[]) {
        NSString *dir = [kBundleRoot stringByAppendingPathComponent:uuid];
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
            if (![name hasSuffix:@".app"]) continue;
            SPAppInfo *a = [self infoFromBundle:[dir stringByAppendingPathComponent:name] system:NO];
            if (a && ![seen containsObject:a.bundleId]) {
                [seen addObject:a.bundleId];
                [list addObject:a];
            }
        }
    }
    // 2) 系统 App
    for (NSString *name in [fm contentsOfDirectoryAtPath:kSystemApps error:NULL] ?: @[]) {
        if (![name hasSuffix:@".app"]) continue;
        SPAppInfo *a = [self infoFromBundle:[kSystemApps stringByAppendingPathComponent:name] system:YES];
        if (a && ![seen containsObject:a.bundleId]) {
            [seen addObject:a.bundleId];
            [list addObject:a];
        }
    }

    [list sortUsingComparator:^NSComparisonResult(SPAppInfo *a, SPAppInfo *b) {
        if ([a.bundleId isEqualToString:@"com.HuQing.Spark"]) return NSOrderedAscending;
        if ([b.bundleId isEqualToString:@"com.HuQing.Spark"]) return NSOrderedDescending;
        return [a.displayName localizedStandardCompare:b.displayName];
    }];
    return list;
}

- (nullable SPAppInfo *)infoFromBundle:(NSString *)path system:(BOOL)system {
    NSString *plist = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
    if (!info) return nil;
    NSString *bid = info[@"CFBundleIdentifier"];
    if (!bid.length) return nil;

    SPAppInfo *a = [SPAppInfo new];
    a.bundleId = bid;
    a.appPath = path;
    a.isSystem = system;
    a.executable = info[@"CFBundleExecutable"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    a.version = info[@"CFBundleShortVersionString"] ?: @"";
    NSString *display = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
    a.displayName = display.length ? display : path.lastPathComponent.stringByDeletingPathExtension;
    return a;
}

- (nullable SPAppInfo *)appWithBundleId:(NSString *)bundleId {
    if (!bundleId.length) return nil;
    for (SPAppInfo *a in [self allApps]) {
        if ([a.bundleId isEqualToString:bundleId]) return a;
    }
    return nil;
}

#pragma mark - 图标

- (nullable UIImage *)iconForBundleId:(NSString *)bundleId size:(CGFloat)size {
    if (!bundleId.length) return nil;
    NSString *key = [NSString stringWithFormat:@"%@@%.0f", bundleId, size];
    UIImage *cached = self.iconCache[key];
    if (cached) return cached;

    // 1) LaunchServices 缓存图标
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (workspaceClass) {
        id ws = nil;
        if ([workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
            ws = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, @selector(defaultWorkspace));
        }
        SEL iconSel = NSSelectorFromString(@"iconForApplicationIdentifier:size:");
        if (ws && [ws respondsToSelector:iconSel]) {
            UIImage *img = ((id (*)(id, SEL, id, double))objc_msgSend)(ws, iconSel, bundleId, (double)size);
            if ([img isKindOfClass:[UIImage class]]) {
                self.iconCache[key] = img;
                return img;
            }
        }
    }

    // 2) 回退：读 .app 里的 png
    SPAppInfo *info = [self appWithBundleId:bundleId];
    if (!info.appPath.length) return nil;
    NSString *plist = [info.appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:plist];
    NSArray *icons = d[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
    NSMutableArray *names = [NSMutableArray array];
    if ([icons isKindOfClass:[NSArray class]]) [names addObjectsFromArray:icons];
    if ([d[@"CFBundleIconFile"] isKindOfClass:[NSString class]]) [names addObject:d[@"CFBundleIconFile"]];

    for (NSString *base in names) {
        for (NSString *suffix in @[@"@3x", @"@2x", @""]) {
            for (NSString *ext in @[@".png", @""]) {
                NSString *file = [NSString stringWithFormat:@"%@%@%@", base, suffix, ext];
                NSString *full = [info.appPath stringByAppendingPathComponent:file];
                UIImage *img = [UIImage imageWithContentsOfFile:full];
                if (img) {
                    self.iconCache[key] = img;
                    return img;
                }
            }
        }
    }
    return nil;
}

@end
