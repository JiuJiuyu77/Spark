//
//  SPIncoming.m
//

#import "SPIncoming.h"
#import "SPStore.h"
#import "SPCompat.h"
#import "SPSession.h"
#import "SPToolchainInstaller.h"

static NSString *const kAppGroup = @"group.com.HuQing.Spark";

@implementation SPIncomingItem
@end

@implementation SPIncoming

+ (instancetype)shared {
    static SPIncoming *i; static dispatch_once_t once;
    dispatch_once(&once, ^{ i = [SPIncoming new]; });
    return i;
}

+ (NSString *)sharedContainerPath {
    NSURL *u = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    return u.path;
}

#pragma mark - 归类

- (SPIncomingKind)kindOfPath:(NSString *)path {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    [fm fileExistsAtPath:path isDirectory:&isDir];
    NSString *name = path.lastPathComponent;
    NSString *lower = name.lowercaseString;

    if (isDir) {
        // 目录里带 Makefile 或 control → 工程
        if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"Makefile"]] ||
            [fm fileExistsAtPath:[path stringByAppendingPathComponent:@"control"]]) {
            return SPIncomingKindProject;
        }
        if ([lower hasSuffix:@".sdk"] || [lower containsString:@"iphoneos"]) return SPIncomingKindSDK;
        if ([lower hasSuffix:@".framework"] || [lower hasSuffix:@".bundle"]) return SPIncomingKindPlugin;
        // 其它目录也当工程候选（用户可能还在准备）
        return SPIncomingKindProject;
    }

    NSString *ext = lower.pathExtension;
    if ([ext isEqualToString:@"dylib"] || [ext isEqualToString:@"framework"] ||
        [ext isEqualToString:@"bundle"]) return SPIncomingKindPlugin;
    if ([ext isEqualToString:@"deb"] || [ext isEqualToString:@"ipa"] ||
        [ext isEqualToString:@"zip"] || [ext isEqualToString:@"tar"] ||
        [ext isEqualToString:@"gz"] || [ext isEqualToString:@"xz"]) {
        if ([lower containsString:@"sdk"]) return SPIncomingKindSDK;
        return SPIncomingKindPackage;
    }
    if ([ext isEqualToString:@"sdk"]) return SPIncomingKindSDK;
    return SPIncomingKindOther;
}

- (NSString *)textForKind:(SPIncomingKind)kind {
    switch (kind) {
        case SPIncomingKindProject: return @"工程";
        case SPIncomingKindPlugin:  return @"插件";
        case SPIncomingKindPackage: return @"安装包";
        case SPIncomingKindSDK:     return @"SDK";
        default:                    return @"其它";
    }
}

- (unsigned long long)sizeOf:(NSString *)path {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    [fm fileExistsAtPath:path isDirectory:&isDir];
    if (!isDir) return [fm attributesOfItemAtPath:path error:NULL].fileSize;
    unsigned long long total = 0;
    for (NSString *rel in [fm subpathsAtPath:path] ?: @[]) {
        total += [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:NULL].fileSize;
    }
    return total;
}

- (SPIncomingItem *)itemAtPath:(NSString *)path {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) return nil;
    SPIncomingItem *it = [SPIncomingItem new];
    it.path = path;
    it.name = path.lastPathComponent;
    it.kind = [self kindOfPath:path];
    it.kindText = [self textForKind:it.kind];
    it.size = [self sizeOf:path];
    return it;
}

#pragma mark - 收件箱

- (NSString *)inbox {
    NSString *dir = [[SPStore shared] inboxDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

- (NSArray<SPIncomingItem *> *)items {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *inbox = [self inbox];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:inbox error:NULL] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *p = [inbox stringByAppendingPathComponent:name];
        SPIncomingItem *it = [self itemAtPath:p];
        if (it) [out addObject:it];
    }
    [out sortUsingComparator:^NSComparisonResult(SPIncomingItem *a, SPIncomingItem *b) {
        NSDate *da = [fm attributesOfItemAtPath:a.path error:NULL][NSFileModificationDate] ?: [NSDate date];
        NSDate *db = [fm attributesOfItemAtPath:b.path error:NULL][NSFileModificationDate] ?: [NSDate date];
        return [db compare:da];
    }];
    return out;
}

- (unsigned long long)totalSize {
    unsigned long long t = 0;
    for (SPIncomingItem *i in [self items]) t += i.size;
    return t;
}

- (void)remove:(SPIncomingItem *)item {
    [[NSFileManager defaultManager] removeItemAtPath:item.path error:NULL];
}

#pragma mark - 导入

- (SPIncomingItem *)importPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) {
        if (error) *error = SPError(SPErrorCodeIO, @"文件不存在");
        return nil;
    }

    // SDK 直接进 SDK 目录
    SPIncomingKind kind = [self kindOfPath:path];
    NSString *dest = nil;
    if (kind == SPIncomingKindSDK) {
        NSString *sdks = [[SPStore shared] sdksDirectory];
        [fm createDirectoryAtPath:sdks withIntermediateDirectories:YES attributes:nil error:NULL];
        dest = [sdks stringByAppendingPathComponent:path.lastPathComponent];
    } else {
        dest = [[self inbox] stringByAppendingPathComponent:path.lastPathComponent];
    }

    // 同名：加时间戳后缀，不覆盖
    if ([fm fileExistsAtPath:dest]) {
        NSString *base = dest.stringByDeletingPathExtension;
        NSString *ext = dest.pathExtension;
        dest = [NSString stringWithFormat:@"%@-%@@%@", base, [SPUtil timestampSlug], ext.length ? ext : @""];
    }

    NSError *err = nil;
    if (![fm copyItemAtPath:path toPath:dest error:&err]) {
        if (error) *error = err;
        return nil;
    }
    return [self itemAtPath:dest];
}

#pragma mark - 收编 Share Extension 的文件

- (NSArray<SPIncomingItem *> *)drainSharedIncoming {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *group = [self.class sharedContainerPath];
    if (!group) return @[];

    NSString *root = [group stringByAppendingPathComponent:@"Incoming"];
    NSMutableArray *jobs = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:NULL] ?: @[]) {
        if ([name hasPrefix:@".receiving-"]) continue;   // 还没写完的跳过
        [jobs addObject:name];
    }
    if (!jobs.count) return @[];

    NSMutableArray<SPIncomingItem *> *out = [NSMutableArray array];
    NSArray *existing = [self items];
    NSMutableSet *existingNames = [NSMutableSet set];
    for (SPIncomingItem *e in existing) [existingNames addObject:e.name];

    for (NSString *job in jobs) {
        NSString *jobDir = [root stringByAppendingPathComponent:job];
        // 每个 job 下面是 00-xxx 这样的子项
        NSArray *children = [fm contentsOfDirectoryAtPath:jobDir error:NULL] ?: @[];
        for (NSString *child in children) {
            NSString *src = [jobDir stringByAppendingPathComponent:child];
            // 去掉 "00-" 前缀还原原名
            NSString *name = child;
            NSRange dash = [child rangeOfString:@"-"];
            if (dash.location == 2 && dash.location != NSNotFound) {
                name = [child substringFromIndex:3];
            }
            if (!name.length) name = child;

            // 同名去重
            NSString *finalName = name;
            NSInteger n = 1;
            while ([existingNames containsObject:finalName]) {
                finalName = [NSString stringWithFormat:@"%@-%ld%@", name.stringByDeletingPathExtension,
                             (long)n++, name.pathExtension.length ? [@"." stringByAppendingString:name.pathExtension] : @""];
            }

            NSString *dest = [[self inbox] stringByAppendingPathComponent:finalName];
            NSError *err = nil;
            BOOL ok = [fm copyItemAtPath:src toPath:dest error:&err];
            if (!ok) {
                SPLog(@"收件失败 %@：%@", src, err.localizedDescription);
                continue;
            }
            [existingNames addObject:finalName];
            SPIncomingItem *it = [self itemAtPath:dest];
            if (it) [out addObject:it];
        }
        // 搬空后删除整个 job
        [fm removeItemAtPath:jobDir error:NULL];
    }
    return out;
}

#pragma mark - 变成项目

- (NSString *)makeProjectFrom:(SPIncomingItem *)item error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    [fm fileExistsAtPath:item.path isDirectory:&isDir];

    NSString *sourceDir = item.path;
    if (!isDir) {
        // 压缩包：解到临时目录
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"import-%@", [SPUtil timestampSlug]]];
        [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *tag = item.path.pathExtension.lowercaseString;
        NSString *cmd = nil;
        if ([tag isEqualToString:@"zip"]) {
            cmd = [NSString stringWithFormat:@"unzip -oq %@ -d %@", [SPUtil shellQuote:item.path], [SPUtil shellQuote:tmp]];
        } else if ([tag isEqualToString:@"deb"]) {
            cmd = [NSString stringWithFormat:@"cd %@ && ar x %@ && (tar xf data.tar.* 2>/dev/null || true)",
                   [SPUtil shellQuote:tmp], [SPUtil shellQuote:item.path]];
        } else if ([tag isEqualToString:@"tar"] || [tag isEqualToString:@"gz"] || [tag isEqualToString:@"xz"]) {
            cmd = [NSString stringWithFormat:@"tar xf %@ -C %@", [SPUtil shellQuote:item.path], [SPUtil shellQuote:tmp]];
        }
        if (!cmd) {
            if (error) *error = SPError(SPErrorCodeUnsupported, @"这个格式不支持解包");
            return nil;
        }
        SPCommandResult *r = [SPSession runSyncShell:cmd
            environment:@{@"PATH": @"/usr/bin:/var/jb/usr/bin:/bin"} cwd:tmp timeout:180];
        if (r.exitCode != 0) {
            if (error) *error = SPError(SPErrorCodeIO, [NSString stringWithFormat:@"解包失败：%@", r.stderrText ?: @""]);
            return nil;
        }
        sourceDir = [self findProjectRootIn:tmp];
        if (!sourceDir) {
            if (error) *error = SPError(SPErrorCodeInvalidProject, @"解包后没找到 Makefile / control");
            return nil;
        }
    }

    // 复制到 projects 目录
    NSString *name = sourceDir.lastPathComponent;
    NSString *projects = [[SPStore shared] projectsDirectory];
    NSString *dest = [projects stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:dest]) {
        dest = [self destinationWithSuffix:projects name:name];
    }
    [fm createDirectoryAtPath:projects withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *err = nil;
    if (![fm copyItemAtPath:sourceDir toPath:dest error:&err]) {
        if (error) *error = err;
        return nil;
    }
    return dest;
}

- (NSString *)destinationWithSuffix:(NSString *)projects name:(NSString *)name {
    NSInteger n = 2;
    NSString *cand = nil;
    do {
        cand = [projects stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%ld", name, (long)n++]];
    } while ([NSFileManager.defaultManager fileExistsAtPath:cand]);
    return cand;
}

/// 在解包目录里找工程根（最多下钻 3 层）
- (nullable NSString *)findProjectRootIn:(NSString *)root {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"Makefile"]]) return root;

    NSString *best = nil;
    for (NSString *rel in [fm subpathsAtPath:root] ?: @[]) {
        if (![rel.lastPathComponent isEqualToString:@"Makefile"]) continue;
        NSString *dir = [root stringByAppendingPathComponent:rel.stringByDeletingLastPathComponent];
        NSInteger depth = [rel componentsSeparatedByString:@"/"].count;
        if (depth <= 4) { best = dir; break; }
    }
    return best;
}

@end
