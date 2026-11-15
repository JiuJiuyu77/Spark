//
//  SPStorage.m
//

#import "SPStorage.h"
#import "SPStore.h"
#import "SPToolchainInstaller.h"
#import "SPCompat.h"

@implementation SPStorageEntry
@end

@implementation SPStorage

+ (instancetype)shared {
    static SPStorage *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SPStorage new]; });
    return s;
}

#pragma mark - 基础

- (unsigned long long)sizeOfPath:(NSString *)path {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
    if (!isDir) return [fm attributesOfItemAtPath:path error:NULL].fileSize;

    unsigned long long total = 0;
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:path];
    NSString *rel;
    while ((rel = [e nextObject])) {
        NSDictionary *a = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:NULL];
        total += a.fileSize;
    }
    return total;
}

- (NSUInteger)countInPath:(NSString *)path {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSUInteger n = 0;
    for (NSString *rel in [fm subpathsAtPath:path] ?: @[]) {
        BOOL isDir = NO;
        [fm fileExistsAtPath:[path stringByAppendingPathComponent:rel] isDirectory:&isDir];
        if (!isDir) n++;
    }
    return n;
}

#pragma mark - 扫描

- (NSArray<SPStorageEntry *> *)scan {
    NSFileManager *fm = NSFileManager.defaultManager;
    SPStore *store = [SPStore shared];
    NSMutableArray *out = [NSMutableArray array];

    // 1. 工程：源码 + 可清理的构建产物
    SPStorageEntry *proj = [SPStorageEntry new];
    proj.category = SPStorageCategoryProjects;
    proj.title = @"工程";
    proj.path = [store projectsDirectory];
    unsigned long long cleanable = 0;
    NSArray *projectNames = [fm contentsOfDirectoryAtPath:proj.path error:NULL] ?: @[];
    for (NSString *name in projectNames) {
        if ([name hasPrefix:@"."]) continue;
        NSString *base = [proj.path stringByAppendingPathComponent:name];
        cleanable += [self sizeOfPath:[base stringByAppendingPathComponent:@".theos"]];
        cleanable += [self sizeOfPath:[base stringByAppendingPathComponent:@"packages"]];
        cleanable += [self sizeOfPath:[base stringByAppendingPathComponent:@"_build"]];
    }
    proj.bytes = [self sizeOfPath:proj.path];
    proj.fileCount = [self countInPath:proj.path];
    proj.cleanableBytes = cleanable;
    [out addObject:proj];

    // 2. 产物
    SPStorageEntry *art = [SPStorageEntry new];
    art.category = SPStorageCategoryArtifacts;
    art.title = @"产物与归档";
    art.path = [store artifactsDirectory];
    art.bytes = [self sizeOfPath:art.path] + [self sizeOfPath:[store archivesDirectory]];
    art.fileCount = [self countInPath:art.path];
    art.cleanableBytes = art.bytes;
    [out addObject:art];

    // 3. 日志
    SPStorageEntry *logs = [SPStorageEntry new];
    logs.category = SPStorageCategoryLogs;
    logs.title = @"日志";
    logs.path = [store logsDirectory];
    logs.bytes = [self sizeOfPath:logs.path];
    logs.fileCount = [self countInPath:logs.path];
    logs.cleanableBytes = logs.bytes;
    [out addObject:logs];

    // 4. 收件箱
    SPStorageEntry *inbox = [SPStorageEntry new];
    inbox.category = SPStorageCategoryInbox;
    inbox.title = @"收件箱";
    inbox.path = [store inboxDirectory];
    inbox.bytes = [self sizeOfPath:inbox.path];
    inbox.fileCount = [self countInPath:inbox.path];
    inbox.cleanableBytes = 0;   // 收件箱要用户自己确认删
    [out addObject:inbox];

    // 5. 工具链
    SPStorageEntry *tc = [SPStorageEntry new];
    tc.category = SPStorageCategoryToolchain;
    tc.title = @"工具链";
    tc.path = [SPToolchainInstaller shared].installRoot;
    tc.bytes = [self sizeOfPath:tc.path];
    tc.fileCount = [self countInPath:tc.path];
    tc.cleanableBytes = 0;      // 工具链删了要重下，不归入「一键清理」
    [out addObject:tc];

    // 6. 缓存（NSTemporaryDirectory 里我们自己的东西）
    SPStorageEntry *caches = [SPStorageEntry new];
    caches.category = SPStorageCategoryCaches;
    caches.title = @"临时缓存";
    caches.path = [self cachePath];
    caches.bytes = [self sizeOfPath:caches.path];
    caches.fileCount = [self countInPath:caches.path];
    caches.cleanableBytes = caches.bytes;
    [out addObject:caches];

    return out;
}

- (NSString *)cachePath {
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Spark"];
    [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:NULL];
    return p;
}

#pragma mark - 清理

- (unsigned long long)removeContentsOf:(NSString *)dir {
    NSFileManager *fm = NSFileManager.defaultManager;
    unsigned long long freed = 0;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
        NSString *p = [dir stringByAppendingPathComponent:name];
        freed += [self sizeOfPath:p];
        [fm removeItemAtPath:p error:NULL];
    }
    return freed;
}

- (unsigned long long)cleanCategory:(SPStorageCategory)category error:(NSError **)error {
    SPStore *store = [SPStore shared];
    switch (category) {
        case SPStorageCategoryArtifacts:
            return [self removeContentsOf:[store artifactsDirectory]]
                 + [self removeContentsOf:[store archivesDirectory]];
        case SPStorageCategoryLogs:
            return [self removeContentsOf:[store logsDirectory]];
        case SPStorageCategoryCaches:
            return [self removeContentsOf:[self cachePath]];
        case SPStorageCategoryInbox:
            return [self removeContentsOf:[store inboxDirectory]];
        case SPStorageCategoryProjects:
            return [self cleanProjectCachesKeeping:nil error:error];
        case SPStorageCategoryToolchain:
            if (error) *error = SPError(SPErrorCodeUnsupported, @"工具链请在「工具链」页逐个删除，避免误删导致构建失败");
            return 0;
        default:
            return 0;
    }
}

- (unsigned long long)cleanProjectCachesKeeping:(NSString *)keepProjectPath error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [[SPStore shared] projectsDirectory];
    unsigned long long freed = 0;

    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:NULL] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *base = [root stringByAppendingPathComponent:name];
        if (keepProjectPath.length && [base isEqualToString:keepProjectPath]) continue;

        for (NSString *sub in @[@".theos", @"packages", @"_build"]) {
            NSString *p = [base stringByAppendingPathComponent:sub];
            if (![fm fileExistsAtPath:p]) continue;
            freed += [self sizeOfPath:p];
            [fm removeItemAtPath:p error:NULL];
        }
    }
    return freed;
}

#pragma mark - 磁盘

- (NSDictionary<NSString *, NSNumber *> *)diskSpace {
    NSError *err = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&err];
    if (!attrs) return @{};
    return @{
        @"total": attrs[NSFileSystemSize] ?: @0,
        @"free": attrs[NSFileSystemFreeSize] ?: @0,
    };
}

@end
