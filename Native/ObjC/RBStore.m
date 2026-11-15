//
//  RBStore.m
//

#import "RBStore.h"
#import "RBCompat.h"
#import <CommonCrypto/CommonDigest.h>

#pragma mark - RBSettings

@interface RBSettings ()
@property (nonatomic, copy) NSString *filePath;
@end

@implementation RBSettings

+ (instancetype)shared {
    static RBSettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [RBSettings new];
        s.projectsRoot = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ReinBuild/projects"];
        s.defaultSDK = @"";
        s.defaultTarget = RBBuildTargetDevice;
        s.sshUser = @"mobile";
        s.sshPort = 22;
        s.githubBranch = @"main";
        s.keepScreenOn = YES;
        s.hapticsOnBuildDone = YES;
        s.maxLogLines = 5000;
        s.showCommandPreview = YES;
        s.filePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ReinBuild/settings.json"];
        [s load];
    });
    return s;
}

- (void)load {
    NSData *d = [NSData dataWithContentsOfFile:self.filePath];
    if (!d) return;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![j isKindOfClass:NSDictionary.class]) return;
    if (j[@"projectsRoot"]) self.projectsRoot = j[@"projectsRoot"];
    if (j[@"defaultSDK"]) self.defaultSDK = j[@"defaultSDK"];
    if (j[@"defaultTarget"]) self.defaultTarget = [j[@"defaultTarget"] integerValue];
    if (j[@"sshHost"]) self.sshHost = j[@"sshHost"];
    if (j[@"sshUser"]) self.sshUser = j[@"sshUser"];
    if (j[@"sshPort"]) self.sshPort = [j[@"sshPort"] integerValue];
    if (j[@"sshKeyPath"]) self.sshKeyPath = j[@"sshKeyPath"];
    if (j[@"githubRepo"]) self.githubRepo = j[@"githubRepo"];
    if (j[@"githubBranch"]) self.githubBranch = j[@"githubBranch"];
    if (j[@"keepScreenOn"]) self.keepScreenOn = [j[@"keepScreenOn"] boolValue];
    if (j[@"haptics"]) self.hapticsOnBuildDone = [j[@"haptics"] boolValue];
    if (j[@"maxLogLines"]) self.maxLogLines = [j[@"maxLogLines"] integerValue];
    if (j[@"showCommandPreview"]) self.showCommandPreview = [j[@"showCommandPreview"] boolValue];
}

- (id)copyWithZone:(NSZone *)zone { return self; } // 单例配置不需要真拷贝

- (void)save {
    NSDictionary *j = @{
        @"projectsRoot": self.projectsRoot ?: @"",
        @"defaultSDK": self.defaultSDK ?: @"",
        @"defaultTarget": @(self.defaultTarget),
        @"sshHost": self.sshHost ?: @"", @"sshUser": self.sshUser ?: @"",
        @"sshPort": @(self.sshPort), @"sshKeyPath": self.sshKeyPath ?: @"",
        @"githubRepo": self.githubRepo ?: @"", @"githubBranch": self.githubBranch ?: @"",
        @"keepScreenOn": @(self.keepScreenOn), @"haptics": @(self.hapticsOnBuildDone),
        @"maxLogLines": @(self.maxLogLines), @"showCommandPreview": @(self.showCommandPreview),
    };
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.filePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingPrettyPrinted error:NULL];
    [d writeToFile:self.filePath atomically:YES];
}

@end

#pragma mark - RBStore

@interface RBStore ()
@property (nonatomic, copy) NSString *base;
@end

@implementation RBStore

+ (instancetype)shared {
    static RBStore *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [RBStore new];
        s.base = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ReinBuild"];
        [s prepare];
    });
    return s;
}

- (NSString *)baseDirectory { return self.base; }

- (void)prepare {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *sub in @[@"", @"projects", @"artifacts", @"logs", @"archives", @"options"]) {
        [fm createDirectoryAtPath:[self.base stringByAppendingPathComponent:sub]
      withIntermediateDirectories:YES attributes:nil error:NULL];
    }
}

- (NSString *)projectsDirectory { return [self.base stringByAppendingPathComponent:@"projects"]; }
- (NSString *)artifactsDirectory { return [self.base stringByAppendingPathComponent:@"artifacts"]; }
- (NSString *)logsDirectory { return [self.base stringByAppendingPathComponent:@"logs"]; }
- (NSString *)archivesDirectory { return [self.base stringByAppendingPathComponent:@"archives"]; }

#pragma mark JSON 读写小工具

- (id)readJSON:(NSString *)name {
    NSData *d = [NSData dataWithContentsOfFile:[self.base stringByAppendingPathComponent:name]];
    if (!d) return nil;
    return [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
}

- (void)writeJSON:(id)obj name:(NSString *)name {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:NULL];
    if (d) [d writeToFile:[self.base stringByAppendingPathComponent:name] atomically:YES];
}

- (NSString *)hashOfPath:(NSString *)path {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *d = [path dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA1(d.bytes, (CC_LONG)d.length, digest);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

#pragma mark 最近项目

- (NSArray<NSDictionary *> *)recentProjects {
    id j = [self readJSON:@"recent.json"];
    return [j isKindOfClass:NSArray.class] ? j : @[];
}

- (void)pushRecentProject:(RBProject *)project {
    if (!project.path.length) return;
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *d in [self recentProjects]) {
        if ([d[@"path"] isEqual:project.path]) continue;
        [list addObject:d];
    }
    [list insertObject:@{
        @"path": project.path, @"name": project.name ?: project.path.lastPathComponent,
        @"kind": project.kindString ?: @"",
        @"opened": @([[NSDate date] timeIntervalSince1970]),
        @"summary": [project.options displaySummary] ?: @"",
    } atIndex:0];
    if (list.count > 30) [list removeObjectsInRange:NSMakeRange(30, list.count - 30)];
    [self writeJSON:list name:@"recent.json"];
}

- (void)removeRecentProjectAtPath:(NSString *)path {
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *d in [self recentProjects]) if (![d[@"path"] isEqual:path]) [list addObject:d];
    [self writeJSON:list name:@"recent.json"];
}

#pragma mark 构建历史

- (NSArray<NSDictionary *> *)buildHistory {
    id j = [self readJSON:@"history.json"];
    return [j isKindOfClass:NSArray.class] ? j : @[];
}

- (void)appendBuildRecord:(RBJob *)job {
    NSMutableArray *list = [NSMutableArray arrayWithObject:[job dictionaryRepresentation]];
    [list addObjectsFromArray:[self buildHistory]];
    if (list.count > 100) [list removeObjectsInRange:NSMakeRange(100, list.count - 100)];
    [self writeJSON:list name:@"history.json"];
}

#pragma mark 选项

- (RBBuildOptions *)optionsForProjectPath:(NSString *)path {
    NSString *name = [NSString stringWithFormat:@"options/%@.json", [self hashOfPath:path]];
    id j = [self readJSON:name];
    if ([j isKindOfClass:NSDictionary.class]) return [RBBuildOptions optionsFromDictionary:j];
    RBBuildOptions *o = [RBBuildOptions new];
    NSString *sdk = RBSettings.shared.defaultSDK;
    if (sdk.length == 0) o.format = RBPackageFormatRootlessDeb;
    return o;
}

- (void)saveOptions:(RBBuildOptions *)options forProjectPath:(NSString *)path {
    NSString *name = [NSString stringWithFormat:@"options/%@.json", [self hashOfPath:path]];
    [self writeJSON:[options dictionaryRepresentation] name:name];
}

#pragma mark 日志落盘

- (NSString *)persistLogText:(NSString *)text jobId:(NSString *)jobId {
    NSString *name = [NSString stringWithFormat:@"%@-%@.log", [RBUtil timestampSlug], jobId];
    NSString *path = [[self logsDirectory] stringByAppendingPathComponent:name];
    BOOL ok = [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES];
    return ok ? path : nil;
}

@end
