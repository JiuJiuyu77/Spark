//
//  SPPrivileged.m
//

#import "SPPrivileged.h"
#import "SPSession.h"
#import "SPCompat.h"
#import <unistd.h>
#import <spawn.h>
#import <errno.h>
#import <string.h>

@implementation SPPrivileged

+ (instancetype)shared {
    static SPPrivileged *p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [SPPrivileged new]; });
    return p;
}

- (uid_t)currentUID { return getuid(); }

/// 能提权的两个条件：当前已是 root，或有 no-sandbox + platform-application
/// （后者只能靠实际试一次确认，这里给保守判断）
- (BOOL)canElevate {
    if (getuid() == 0) return YES;
    // 能读 /private/var/containers/Bundle/Application 基本说明平台权限已生效
    return [[NSFileManager defaultManager] isReadableFileAtPath:@"/private/var/containers/Bundle/Application"];
}

- (NSString *)statusText {
    if (getuid() == 0) return [NSString stringWithFormat:@"root（uid 0）"];
    if (self.canElevate) {
        return [NSString stringWithFormat:@"当前 uid %d · 可提权运行子进程", (int)getuid()];
    }
    return [NSString stringWithFormat:@"当前 uid %d · 无提权能力（需 TrollStore 安装）", (int)getuid()];
}

- (BOOL)elevateSelf {
    if (getuid() == 0) {
        SPLog(@"已是 root（uid 0）");
        return YES;
    }

    uid_t before = getuid();
    uid_t egid_before = getegid();

    // 把失败原因记全：之前只有一句 strerror，看不出是「权限不够」
    // 还是「沙盒拦了」，也就无从判断该怎么办。
    SPLog(@"提权尝试：euid=%d ruid=%d egid=%d", (int)geteuid(), (int)before, (int)egid_before);

    if (setgid(0) != 0) {
        int e = errno;
        SPLog(@"setgid(0) 失败 errno=%d (%s)", e, strerror(e));
    }
    if (setuid(0) != 0) {
        int e = errno;
        SPLog(@"setuid(0) 失败 errno=%d (%s)", e, strerror(e));
        // EPERM(1) = 系统拒绝：通常是 ipa 没用 platform-application 签名，
        //             或者启动它的进程本身不是 root（TrollStore 的 ldid 签名链断了）
        if (e == EPERM) {
            SPLog(@"[!] EPERM 说明进程没有提权能力：ipa 的签名里缺 platform-application，"
                  @"或不是通过 TrollStore 安装。");
        }
        setuid(before);
        return NO;
    }
    SPLog(@"已提权：uid %d → %d", (int)before, (int)getuid());
    return getuid() == 0;
}

- (BOOL)ensureRoot {
    if (getuid() == 0) return YES;
    // 重试 3 次：setuid(0) 在某些环境下会因瞬时状态失败
    for (int i = 0; i < 3; i++) {
        if ([self elevateSelf]) return YES;
        usleep(120 * 1000);
    }
    SPLog(@"[!] ensureRoot 失败：当前 uid=%d，子进程将以非 root 运行", (int)getuid());
    return NO;
}

- (void)verifyChildRunsAsRoot:(void (^)(BOOL, uid_t, NSString *))completion {
    // 用一条最短命令取子进程真实 uid。
    // 注意：这里不看父进程的 getuid()，父进程是 root 不代表
    // posix_spawn 出来的子进程也是（继承链路可能被降权）。
    SPSession *s = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:NSTemporaryDirectory()];
    s.timeout = 10;
    __block NSString *out = @"";
    s.onLine = ^(NSString *line, SPLogLevel lv) {
        if (line.length) out = [out stringByAppendingFormat:@"%@\n", line];
    };
    s.onFinish = ^(SPCommandResult *r) {
        NSString *text = r.stdoutText ?: out;
        uid_t uid = (uid_t)-1;
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSString *t = [line stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (t.length && [[NSCharacterSet decimalDigitCharacterSet]
                             isSupersetOfSet:[NSCharacterSet characterSetWithCharactersInString:t]]) {
                uid = (uid_t)t.intValue;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(uid == 0, uid,
                    [NSString stringWithFormat:@"子进程 uid=%d（%@）",
                     (int)uid, uid == 0 ? @"root" : @"非 root，编译会失败"]);
            }
        });
    };
    [s runShell:@"id -u"];
}

#pragma mark - 探活

- (void)probeWithCompletion:(void (^)(NSString *))completion {
    // 自检要能回答「为什么不是 root」：
    //   App 自身 uid、能否 setuid、子进程实际 uid、shell 在哪、能否写临时目录
    NSString *probe =
        @"echo \"APP_UID=$(id -u) APP_GID=$(id -g)\"; "
         "echo \"SHELL=$(command -v sh || echo none)\"; "
         "echo \"SUB_UID=$(id -u)\"; "
         "echo \"SUB_GID=$(id -g)\"; "
         "echo \"HOME=$HOME\"; "
         "T=/tmp/spark-probe-$$; "
         "if mkdir -p \"$T\" 2>/dev/null && touch \"$T/x\" 2>/dev/null; then "
         "echo \"TMP_WRITE=yes\"; rm -rf \"$T\"; else echo \"TMP_WRITE=no\"; fi; "
         "for b in make clang-16 ld64 ldid dpkg-deb perl; do "
         "  p=$(command -v $b 2>/dev/null); echo \"TOOL_$b=${p:-missing}\"; done";

    [self runAsRoot:probe completion:^(BOOL ok, BOOL wasRoot, NSString *output) {
        // 同时列出父进程与子进程身份：
        // 「父进程是 root 但子进程不是」这种情况最容易误判，
        // 必须分开看。
        NSString *detail = [NSString stringWithFormat:
            @"父进程 uid = %d（%@）\n"
             "子进程 uid = %@\n\n"
             "%@\n\n%@",
            (int)getuid(),
            getuid() == 0 ? @"root" : @"非 root",
            wasRoot ? @"0（root）" : @"非 0",
            wasRoot ? @"✓ 子进程以 root 运行"
                    : @"✗ 子进程以普通用户运行 —— 编译会失败\n"
                      @"原因通常是：Spark 不是通过 TrollStore 安装，\n"
                      @"或安装时缺少 platform-application 权限。",
            output ?: @""];
        if (completion) completion(detail);
    }];
}

#pragma mark - 以 root 执行

- (void)runAsRoot:(NSString *)script completion:(void (^)(BOOL, BOOL, NSString *))completion {
    NSString *body = script ?: @"";
    // 在脚本最前面尝试 seteuid(0)：已是 root 时无害，不是则失败并继续原身份
    // 只探测身份，不做任何提权 hack（chmod u+s 会留后门且通常无效）
    NSString *wrapped = [NSString stringWithFormat:
        @"echo SPARK_UID=$(id -u)\n"
         "echo SPARK_GID=$(id -g)\n"
         "%@\n", body];

    SPSession *session = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:NSTemporaryDirectory()];
    NSMutableString *log = [NSMutableString string];
    // NSMutableString 不是线程安全的：onLine 在后台读线程回调，
    // onFinish 在另一线程读它，必须加锁，否则可能拿到半写状态
    // （表现是日志乱码、丢行，甚至崩溃）。
    session.onLine = ^(NSString *line, SPLogLevel level) {
        @synchronized (log) {
            [log appendString:line];
            [log appendString:@"\n"];
        }
    };
    session.onFinish = ^(SPCommandResult *r) {
        NSString *out = nil;
        @synchronized (log) { out = log.length ? [log copy] : (r.stderrText ?: @""); }
        BOOL wasRoot = [out containsString:@"SPARK_UID=0"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(r.exitCode == 0, wasRoot, out);
        });
    };

    // 如果已经具备提权能力，就尝试切到 root（TrollStore 下通常直接就是）
    if (getuid() != 0 && self.canElevate) {
        if (setuid(0) != 0) {
            SPLog(@"setuid(0) 失败：%s（保持当前身份继续）", strerror(errno));
        }
    }
    [session runShell:wrapped];
}

@end
