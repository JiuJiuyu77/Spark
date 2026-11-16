//
//  SPInstall.m
//

#import "SPInstall.h"
#import "SPSession.h"
#import "SPToolchainInstaller.h"
#import "SPCompat.h"

@implementation SPInstallTask
@end

@interface SPInstall ()
@property (nonatomic, strong) NSArray<NSString *> *searchDirs;
@end

@implementation SPInstall

+ (instancetype)shared {
    static SPInstall *i; static dispatch_once_t once;
    dispatch_once(&once, ^{
        i = [SPInstall new];
        NSMutableArray *d = [NSMutableArray array];
        NSString *bin = SPToolchainInstallerBinDir();
        if (bin.length) [d addObject:bin];
        SPToolchainInstaller *inst = [SPToolchainInstaller shared];
        if (inst.isInstalled) {
            [d addObject:[inst.installRoot stringByAppendingPathComponent:@"coretools/usr/bin"]];
            [d addObject:[inst.installRoot stringByAppendingPathComponent:@"coretools/bin"]];
        }
        [d addObjectsFromArray:@[@"/var/jb/usr/bin", @"/usr/bin", @"/usr/local/bin", @"/bin"]];
        i.searchDirs = d;
    });
    return i;
}

#pragma mark - 探测

- (SPInstallKind)kindOfPath:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"deb"]) return SPInstallKindDeb;
    if ([ext isEqualToString:@"dylib"]) return SPInstallKindDylib;
    return SPInstallKindApp;
}

- (NSString *)packageIdOfDeb:(NSString *)path {
    NSString *dpkgDeb = [SPUtil findExecutable:@[@"dpkg-deb"] searchDirs:self.searchDirs];
    if (!dpkgDeb) return nil;
    NSString *cmd = [NSString stringWithFormat:@"%@ -f %@ Package 2>/dev/null",
                     [SPUtil shellQuote:dpkgDeb], [SPUtil shellQuote:path]];
    SPCommandResult *r = [SPSession runSyncShell:cmd environment:@{} cwd:NSTemporaryDirectory() timeout:20];
    NSString *out = [r.stdoutText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return out.length ? out : nil;
}

- (NSString *)versionOfDeb:(NSString *)path {
    NSString *dpkgDeb = [SPUtil findExecutable:@[@"dpkg-deb"] searchDirs:self.searchDirs];
    if (!dpkgDeb) return nil;
    NSString *cmd = [NSString stringWithFormat:@"%@ -f %@ Version 2>/dev/null",
                     [SPUtil shellQuote:dpkgDeb], [SPUtil shellQuote:path]];
    SPCommandResult *r = [SPSession runSyncShell:cmd environment:@{} cwd:NSTemporaryDirectory() timeout:20];
    NSString *out = [r.stdoutText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return out.length ? out : nil;
}

- (SPInstallTask *)inspectPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
        if (error) *error = SPError(SPErrorCodeIO, @"文件不存在");
        return nil;
    }

    SPInstallTask *t = [SPInstallTask new];
    t.path = path;
    t.kind = [self kindOfPath:path];

    if (t.kind == SPInstallKindApp && isDir) {
        NSString *plist = [path stringByAppendingPathComponent:@"Info.plist"];
        t.title = [SPUtil stringFromPlistAtPath:plist key:@"CFBundleDisplayName" default:path.lastPathComponent.stringByDeletingPathExtension];
        t.packageId = [SPUtil stringFromPlistAtPath:plist key:@"CFBundleIdentifier" default:@""];
        t.version = [SPUtil stringFromPlistAtPath:plist key:@"CFBundleShortVersionString" default:@""];
    } else if (t.kind == SPInstallKindDeb) {
        t.packageId = [self packageIdOfDeb:path];
        t.version = [self versionOfDeb:path];
        t.title = t.packageId.length ? t.packageId : path.lastPathComponent;
    } else {
        t.title = path.lastPathComponent;
    }
    return t;
}

- (NSArray<NSString *> *)installedPackageIds {
    NSString *dpkg = [SPUtil findExecutable:@[@"dpkg"] searchDirs:self.searchDirs];
    if (!dpkg) return @[];
    SPCommandResult *r = [SPSession runSyncShell:[NSString stringWithFormat:@"%@ -l 2>/dev/null | awk '{print $2}' | tail -n +6", [SPUtil shellQuote:dpkg]]
        environment:@{} cwd:NSTemporaryDirectory() timeout:20];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [r.stdoutText componentsSeparatedByString:@"\n"]) {
        NSString *s = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (s.length) [out addObject:s];
    }
    return out;
}

#pragma mark - 安装

- (void)runScript:(NSString *)script completion:(void (^)(BOOL, NSString *))completion {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[@"PATH"] = [self.searchDirs componentsJoinedByString:@":"];
    SPSession *s = [[SPSession alloc] initWithEnvironment:env workingDirectory:NSTemporaryDirectory()];
    NSMutableString *log = [NSMutableString string];
    s.onLine = ^(NSString *line, SPLogLevel level) {
        // 后台读线程回调，与 onFinish 的读取互斥
        @synchronized (log) {
            [log appendString:line];
            [log appendString:@"\n"];
        }
    };
    s.onFinish = ^(SPCommandResult *r) {
        NSString *out = nil;
        @synchronized (log) { out = log.length ? [log copy] : (r.stderrText ?: @""); }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(r.exitCode == 0, out);
        });
    };
    s.timeout = 180;
    [s runShell:script];
}

- (void)installTask:(SPInstallTask *)task completion:(void (^)(BOOL, NSString *))completion {
    switch (task.kind) {
        case SPInstallKindDeb: {
            NSString *dpkg = [SPUtil findExecutable:@[@"dpkg"] searchDirs:self.searchDirs];
            if (!dpkg) {
                if (completion) completion(NO, @"找不到 dpkg（需要 CoreTools 运行时）");
                return;
            }
            // --force-overwrite：插件常常覆盖同名文件，不加会装不上
            NSString *script = [NSString stringWithFormat:
                @"say(){ printf '==> %%s\\n' \"$1\"; }\n"
                 "say '安装 deb'\n"
                 "echo '  %@'\n"
                 "%@ -i --force-overwrite %@ 2>&1\n"
                 "rc=$?\n"
                 "if [ $rc -eq 0 ]; then echo '[ok] 安装完成'; else echo \"[!] dpkg 退出码 $rc\"; fi\n"
                 "exit $rc\n",
                task.title, [SPUtil shellQuote:dpkg], [SPUtil shellQuote:task.path]];
            [self runScript:script completion:completion];
            break;
        }
        case SPInstallKindApp: {
            // 交给 TrollStore：用 troller 命令（TrollStore 自带）或 open URL
            NSString *script = [NSString stringWithFormat:
                @"say(){ printf '==> %%s\\n' \"$1\"; }\n"
                 "P=%@\n"
                 "say '交给 TrollStore 安装'\n"
                 "for T in /var/jb/usr/bin/troller /usr/bin/troller /var/mobile/Documents/troller; do\n"
                 "  if [ -x \"$T\" ]; then echo \"  使用 $T\"; \"$T\" install \"$P\" 2>&1; exit $?; fi\n"
                 "done\n"
                 "echo '  找不到 troller，改用 open'\n"
                 "open \"$P\" 2>&1 || exit 2\n",
                [SPUtil shellQuote:task.path]];
            [self runScript:script completion:completion];
            break;
        }
        case SPInstallKindDylib: {
            NSString *script = [NSString stringWithFormat:
                @"say(){ printf '==> %%s\\n' \"$1\"; }\n"
                 "SRC=%@\n"
                 "NAME=$(basename \"$SRC\")\n"
                 "say '拷到插件目录'\n"
                 "for D in /var/jb/Library/MobileSubstrate/DynamicLibraries \\\n"
                 "         /Library/MobileSubstrate/DynamicLibraries; do\n"
                 "  if [ -d \"$D\" ]; then\n"
                 "    cp \"$SRC\" \"$D/$NAME\" && echo \"  → $D/$NAME\"\n"
                 "    chown mobile:mobile \"$D/$NAME\" 2>/dev/null || true\n"
                 "    chmod 755 \"$D/$NAME\"\n"
                 "    exit 0\n"
                 "  fi\n"
                 "done\n"
                 "echo '[!] 没找到插件目录'; exit 2\n",
                [SPUtil shellQuote:task.path]];
            [self runScript:script completion:completion];
            break;
        }
    }
}

- (void)uninstallPackageId:(NSString *)packageId completion:(void (^)(BOOL, NSString *))completion {
    NSString *dpkg = [SPUtil findExecutable:@[@"dpkg"] searchDirs:self.searchDirs];
    if (!dpkg) {
        if (completion) completion(NO, @"找不到 dpkg");
        return;
    }
    NSString *script = [NSString stringWithFormat:
        @"say(){ printf '==> %%s\\n' \"$1\"; }\n"
         "say '卸载 %@'\n"
         "%@ -r %@ 2>&1\n"
         "rc=$?\n"
         "if [ $rc -eq 0 ]; then echo '[ok] 已卸载'; fi\n"
         "exit $rc\n",
        packageId, [SPUtil shellQuote:dpkg], [SPUtil shellQuote:packageId]];
    [self runScript:script completion:completion];
}

@end
