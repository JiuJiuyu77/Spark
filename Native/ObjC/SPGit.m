//
//  SPGit.m
//

#import "SPGit.h"
#import "SPSession.h"
#import "SPToolchainInstaller.h"
#import "SPCompat.h"
#import "SPStore.h"

@implementation SPGitFileStatus
@end

@implementation SPGitCommit
@end

@interface SPGit ()
@property (nonatomic, copy, nullable) NSString *gitPath;
@property (nonatomic, strong) NSArray<NSString *> *searchDirs;
@end

@implementation SPGit

+ (instancetype)shared {
    static SPGit *g; static dispatch_once_t once;
    dispatch_once(&once, ^{
        g = [SPGit new];
        NSMutableArray *dirs = [NSMutableArray array];
        SPToolchainInstaller *inst = [SPToolchainInstaller shared];
        if (inst.isInstalled) {
            [dirs addObject:[inst.installRoot stringByAppendingPathComponent:@"coretools/bin"]];
            [dirs addObject:[inst.installRoot stringByAppendingPathComponent:@"coretools/usr/bin"]];
            [dirs addObject:inst.binDir];
        }
        [dirs addObjectsFromArray:@[@"/var/jb/usr/bin", @"/usr/bin", @"/usr/local/bin", @"/bin"]];
        g.searchDirs = dirs;
        g.gitPath = [SPUtil findExecutable:@[@"git"] searchDirs:dirs];
    });
    return g;
}

+ (dispatch_queue_t)queue {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.huging.spark.git", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

#pragma mark - 执行

/// 同步跑一条 git 命令，返回 stdout（失败时填充 error）
- (nullable NSString *)runGit:(NSArray<NSString *> *)args
                          root:(NSString *)root
                         error:(NSError **)error
                    extraEnv:(nullable NSDictionary<NSString *, NSString *> *)extraEnv {
    if (!self.gitPath) {
        if (error) *error = SPError(SPErrorCodeMissingToolchain, @"找不到 git，请先在工具链页下载「核心工具集」");
        return nil;
    }

    NSMutableString *cmd = [NSMutableString string];
    // 关掉分页与交互提示，避免卡住
    [cmd appendString:@"export GIT_PAGER=cat PAGER=cat GIT_TERMINAL_PROMPT=0\n"];
    [cmd appendString:[NSString stringWithFormat:@"cd %@ || exit 9\n", [SPUtil shellQuote:root]]];
    [cmd appendString:[SPUtil shellQuote:self.gitPath]];
    for (NSString *a in args) {
        [cmd appendString:@" "];
        [cmd appendString:[SPUtil shellQuote:a]];
    }
    [cmd appendString:@" 2>&1\n"];

    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[@"PATH"] = [self.searchDirs componentsJoinedByString:@":"];
    env[@"HOME"] = NSHomeDirectory();
    // 让 git 别去找系统用户，避免 "dubious ownership"
    env[@"GIT_CONFIG_NOSYSTEM"] = @"1";
    if (extraEnv) [env addEntriesFromDictionary:extraEnv];

    SPCommandResult *r = [SPSession runSyncShell:cmd environment:env cwd:root timeout:120];
    NSString *out = r.stdoutText ?: @"";
    if (r.exitCode != 0) {
        if (error) {
            NSString *msg = out.length ? out : (r.stderrText ?: @"git 执行失败");
            *error = SPError(SPErrorCodeNonZeroExit, msg.length > 600 ? [msg substringToIndex:600] : msg);
        }
        return nil;
    }
    return out;
}

#pragma mark - 状态

- (BOOL)isRepository:(NSString *)root {
    NSError *err = nil;
    return [self runGit:@[@"rev-parse", @"--git-dir"] root:root error:&err extraEnv:nil] != nil;
}

- (NSDictionary *)statusAtRoot:(NSString *)root error:(NSError **)error {
    if (![self isRepository:root]) {
        if (error) *error = SPError(SPErrorCodeInvalidProject, @"这不是一个 git 仓库");
        return nil;
    }
    NSString *out = [self runGit:@[@"status", @"--porcelain=v1", @"--branch"] root:root error:error extraEnv:nil];
    if (!out) return nil;

    NSMutableArray<SPGitFileStatus *> *files = [NSMutableArray array];
    NSString *branch = @"";
    NSInteger ahead = 0, behind = 0;

    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        if ([line hasPrefix:@"## "]) {
            NSString *head = [line substringFromIndex:3];
            NSRange dots = [head rangeOfString:@"..."];
            branch = dots.location == NSNotFound ? head : [head substringToIndex:dots.location];
            if ([branch hasPrefix:@"No commits"]) branch = @"(空仓库)";
            NSRange ab = [head rangeOfString:@"[ahead "];
            if (ab.location != NSNotFound) {
                NSArray *parts = [[head substringFromIndex:ab.location] componentsSeparatedByString:@" "];
                if (parts.count > 1) ahead = [parts[1] integerValue];
            }
            continue;
        }
        if (line.length < 4) continue;

        NSString *xy = [line substringToIndex:2];
        NSString *path = [line substringFromIndex:3];
        // 重命名：old -> new，取新的
        NSRange arrow = [path rangeOfString:@" -> "];
        if (arrow.location != NSNotFound) path = [path substringFromIndex:arrow.location + 4];

        SPGitFileStatus *f = [SPGitFileStatus new];
        f.path = path;
        f.staged = (xy.length > 0 && [xy characterAtIndex:0] != ' ' && [xy characterAtIndex:0] != '?');
        f.untracked = [xy hasPrefix:@"??"];
        unichar idx = [xy characterAtIndex:0];
        unichar wt = xy.length > 1 ? [xy characterAtIndex:1] : ' ';
        unichar c = (idx != ' ') ? idx : wt;
        f.status = [NSString stringWithFormat:@"%c", c];
        if (f.untracked) f.status = @"??";
        [files addObject:f];
    }

    return @{
        @"branch": branch, @"ahead": @(ahead), @"behind": @(behind),
        @"files": files, @"raw": out,
    };
}

- (NSString *)currentBranchRoot:(NSString *)root {
    NSString *out = [self runGit:@[@"rev-parse", @"--abbrev-ref", @"HEAD"] root:root error:NULL extraEnv:nil];
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

#pragma mark - 初始化 / 暂存

- (BOOL)initializeRoot:(NSString *)root error:(NSError **)error {
    return [self runGit:@[@"init"] root:root error:error extraEnv:nil] != nil;
}

- (BOOL)stagePaths:(NSArray<NSString *> *)paths root:(NSString *)root error:(NSError **)error {
    if (!paths.count) {
        // 全量
        return [self runGit:@[@"add", @"-A"] root:root error:error extraEnv:nil] != nil;
    }
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"add"];
    [args addObjectsFromArray:paths];
    return [self runGit:args root:root error:error extraEnv:nil] != nil;
}

- (BOOL)unstagePaths:(NSArray<NSString *> *)paths root:(NSString *)root error:(NSError **)error {
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"reset", @"HEAD", @"--", nil];
    if (paths.count) [args addObjectsFromArray:paths];
    // 空仓库没有 HEAD，退回 rm --cached
    NSError *err = nil;
    if ([self runGit:args root:root error:&err extraEnv:nil]) return YES;

    NSMutableArray *fallback = [NSMutableArray arrayWithObjects:@"rm", @"--cached", @"-r", @"--", nil];
    if (paths.count) [fallback addObjectsFromArray:paths];
    else [fallback addObject:@"."];
    return [self runGit:fallback root:root error:error extraEnv:nil] != nil;
}

#pragma mark - 提交

- (NSString *)commitRoot:(NSString *)root
                 message:(NSString *)message
                    name:(NSString *)name
                   email:(NSString *)email
                   error:(NSError **)error {
    if (!message.length) {
        if (error) *error = SPError(SPErrorCodeIO, @"提交信息不能为空");
        return nil;
    }
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    // 仓库没配 user.name 时 git 会报错，这里用环境变量兜底（不写进仓库配置）
    if (name.length) {
        env[@"GIT_AUTHOR_NAME"] = name;
        env[@"GIT_COMMITTER_NAME"] = name;
    }
    if (email.length) {
        env[@"GIT_AUTHOR_EMAIL"] = email;
        env[@"GIT_COMMITTER_EMAIL"] = email;
    }

    if (![self runGit:@[@"commit", @"-m", message] root:root error:error extraEnv:env]) return nil;

    NSString *hash = [self runGit:@[@"rev-parse", @"--short", @"HEAD"] root:root error:NULL extraEnv:nil];
    return [hash stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

#pragma mark - 差异 / 历史

- (NSString *)diffRoot:(NSString *)root path:(NSString *)path staged:(BOOL)staged {
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"diff"];
    if (staged) [args addObject:@"--cached"];
    if (path.length) [args addObjectsFromArray:@[@"--", path]];
    NSString *out = [self runGit:args root:root error:NULL extraEnv:nil];
    return out.length ? out : @"（没有差异）";
}

- (NSArray<SPGitCommit *> *)historyRoot:(NSString *)root limit:(NSInteger)limit {
    NSString *sep = @"\x1f";
    NSString *fmt = [NSString stringWithFormat:@"%%H%@%%h%@%%an%@%%ar%@%%s", sep, sep, sep, sep];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"log", @"--pretty=format:", nil];
    [args addObject:fmt];
    [args addObject:[NSString stringWithFormat:@"-n%ld", (long)MAX(1, limit)]];
    NSString *out = [self runGit:args root:root error:NULL extraEnv:nil];
    if (!out.length) return @[];

    NSMutableArray<SPGitCommit *> *list = [NSMutableArray array];
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSArray *p = [line componentsSeparatedByString:sep];
        if (p.count < 5) continue;
        SPGitCommit *c = [SPGitCommit new];
        c.hash = p[0];
        c.shortHash = p[1];
        c.author = p[2];
        c.date = p[3];
        c.message = p[4];
        [list addObject:c];
    }
    return list;
}

#pragma mark - 远端 / 推送

- (BOOL)setRemoteRoot:(NSString *)root url:(NSString *)url error:(NSError **)error {
    if (!url.length) {
        if (error) *error = SPError(SPErrorCodeIO, @"远端地址不能为空");
        return NO;
    }
    // 已有 origin 就先删再加（幂等）
    [self runGit:@[@"remote", @"remove", @"origin"] root:root error:NULL extraEnv:nil];
    return [self runGit:@[@"remote", @"add", @"origin", url] root:root error:error extraEnv:nil] != nil;
}

- (NSString *)pushRoot:(NSString *)root
                remote:(NSString *)remote
                branch:(NSString *)branch
                 token:(nullable NSString *)token
                 error:(NSError **)error {
    if (!token.length) {
        if (error) *error = SPError(SPErrorCodeIO, @"需要 GitHub token 才能推送");
        return nil;
    }
    // 用 credential helper 临时注入 token（不写进 .git/config）
    NSString *helper = @"!f() { echo username=x-access-token; echo password=$SPARK_GH_TOKEN; }; f";
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[@"SPARK_GH_TOKEN"] = token;

    NSMutableArray *args = [NSMutableArray arrayWithObjects:
        @"-c", [@"credential.helper=" stringByAppendingString:helper], @"push", nil];
    if (remote.length) [args addObject:remote];
    if (branch.length) [args addObject:branch];
    else [args addObject:@"HEAD"];
    [args addObject:@"--set-upstream"];

    NSString *out = [self runGit:args root:root error:error extraEnv:env];
    return out ?: nil;
}

#pragma mark - 编译前自动快照

- (BOOL)snapshotBeforeBuild:(NSString *)root
                     reason:(NSString *)reason
                      error:(NSError **)error {
    if (![self isRepository:root]) return NO;

    // 先看有没有未提交改动
    NSDictionary *st = [self statusAtRoot:root error:NULL];
    NSArray<SPGitFileStatus *> *files = st[@"files"];
    if (![files isKindOfClass:[NSArray class]] || files.count == 0) return NO;

    // 全部暂存
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (SPGitFileStatus *f in files) {
        if (f.path.length) [paths addObject:f.path];
    }
    NSError *err = nil;
    if (paths.count && ![self stagePaths:paths root:root error:&err]) {
        if (error) *error = err;
        return NO;
    }

    NSString *msg = [NSString stringWithFormat:@"chore(snapshot): 编译前自动保存 %@",
                     reason.length ? reason : @"构建"];
    SPSettings *cfg = SPSettings.shared;
    NSString *hash = [self commitRoot:root
                              message:msg
                                 name:(cfg.gitUserName.length ? cfg.gitUserName : @"Workbench")
                                email:(cfg.gitUserEmail.length ? cfg.gitUserEmail : @"workbench@localhost")
                                error:&err];
    if (!hash) {
        if (error) *error = err;
        return NO;
    }
    SPLog(@"已自动快照：%@ (%@)", msg, hash);
    return YES;
}

@end
