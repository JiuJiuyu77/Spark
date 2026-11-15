//
//  SPSession.m
//

#import "SPSession.h"
#import "SPCompat.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <string.h>

extern char **environ;

#pragma mark - SPCommandResult

@implementation SPCommandResult
- (BOOL)ok { return self.exitCode == 0 && !self.cancelled && !self.timedOut && !self.launchError; }
@end

#pragma mark - SPSession

@interface SPSession ()
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) int outFd;
@property (nonatomic, assign) int errFd;
@property (nonatomic, strong) NSMutableString *outBuf;
@property (nonatomic, strong) NSMutableString *errBuf;
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, assign) BOOL cancelRequested;
@property (nonatomic, assign) BOOL timedOut;
@property (nonatomic, copy) SPCommandResult *result;
@property (nonatomic, strong) dispatch_queue_t readQueue;
@property (nonatomic, assign) BOOL finished;
@end

@implementation SPSession

/// 环境变量只保留 NSString 值：其它类型（NSNull/NSNumber/嵌套）一律转成字符串，
/// 否则 copy 时会在 -forwardingTargetForSelector: 上抛异常直接 abort。
static NSDictionary<NSString *, NSString *> *SPSanitizeEnvironment(NSDictionary *env) {
    if (![env isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id key in env) {
        if (![key isKindOfClass:NSString.class]) continue;
        id value = env[key];
        if ([value isKindOfClass:NSString.class]) {
            out[key] = value;
        } else if ([value isKindOfClass:NSNumber.class]) {
            out[key] = [value stringValue];
        } else if (value == nil || [value isKindOfClass:NSNull.class]) {
            out[key] = @"";
        } else {
            out[key] = [value description] ?: @"";
        }
    }
    return [out copy];
}

- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)env
                   workingDirectory:(NSString *)cwd {
    if ((self = [super init])) {
        _environment = SPSanitizeEnvironment(env);
        _workingDirectory = [cwd isKindOfClass:NSString.class] ? [cwd copy] : nil;
        _outBuf = [NSMutableString string];
        _errBuf = [NSMutableString string];
        _readQueue = dispatch_queue_create("spark.session.read", DISPATCH_QUEUE_SERIAL);
        _pid = -1; _outFd = -1; _errFd = -1;
    }
    return self;
}

- (BOOL)isRunning { return self.pid > 0 && !self.finished; }

- (void)setEnvironment:(NSDictionary<NSString *, NSString *> *)environment {
    _environment = SPSanitizeEnvironment(environment);
}

#pragma mark 环境组装

- (NSArray<NSString *> *)environmentStrings {
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];
    for (char **e = environ; e && *e; e++) {
        NSString *kv = [NSString stringWithUTF8String:*e];
        NSRange r = [kv rangeOfString:@"="]; if (r.location == NSNotFound) continue;
        merged[[kv substringToIndex:r.location]] = [kv substringFromIndex:r.location + 1];
    }
    [merged addEntriesFromDictionary:self.environment];
    if (!merged[@"HOME"]) merged[@"HOME"] = NSHomeDirectory();
    if (!merged[@"LANG"]) merged[@"LANG"] = @"en_US.UTF-8";
    if (!merged[@"TERM"]) merged[@"TERM"] = @"dumb";
    return [SPUtil envPairsFromDictionary:merged];
}

#pragma mark 启动

- (int)launch:(NSString *)exe args:(NSArray<NSString *> *)args {
    if (self.isRunning) return -1;

    int pfd[2], efd[2];
    if (pipe(pfd) != 0) return -1;
    if (pipe(efd) != 0) { close(pfd[0]); close(pfd[1]); return -1; }

    pid_t child = -1;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pfd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, efd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pfd[0]);
    posix_spawn_file_actions_addclose(&actions, efd[0]);
    // 注意：posix_spawn_file_actions_addchdir_np 在 iOS 上不可用（SDK 标记为 unavailable），
    // 所以工作目录统一在 runShell 里用 `cd` 完成，这里不再处理。

    // 会话独立，方便整组 kill
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF);
    posix_spawnattr_setpgroup(&attr, 0);
    sigset_t defs; sigemptyset(&defs); sigaddset(&defs, SIGPIPE);
    posix_spawnattr_setsigdefault(&attr, &defs);

    // argv
    NSMutableArray *argvArr = [NSMutableArray arrayWithObject:exe];
    [argvArr addObjectsFromArray:args];
    char **argv = calloc(argvArr.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvArr.count; i++) {
        id a = argvArr[i];
        const char *cstr = [a isKindOfClass:NSString.class] ? [(NSString *)a UTF8String] : "";
        argv[i] = strdup(cstr ? cstr : "");
    }
    argv[argvArr.count] = NULL;

    NSArray *envArr = [self environmentStrings];
    char **envp = calloc(envArr.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < envArr.count; i++) {
        id a = envArr[i];
        const char *cstr = [a isKindOfClass:NSString.class] ? [(NSString *)a UTF8String] : "";
        envp[i] = strdup(cstr ? cstr : "");
    }
    envp[envArr.count] = NULL;

    int rc = posix_spawn(&child, exe.fileSystemRepresentation, &actions, &attr, argv, envp);
    int savedErrno = errno;

    for (NSUInteger i = 0; i < argvArr.count; i++) free(argv[i]);
    free(argv);
    for (NSUInteger i = 0; i < envArr.count; i++) free(envp[i]);
    free(envp);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);

    close(pfd[1]); close(efd[1]);

    if (rc != 0) {
        close(pfd[0]); close(efd[0]);
        SPCommandResult *r = [SPCommandResult new];
        r.exitCode = -1;
        r.launchError = SPError(SPErrorCodeLaunchFailed,
            [NSString stringWithFormat:@"无法启动 %@：%s", exe.lastPathComponent, strerror(savedErrno)]);
        self.result = r;
        [self finishNotifying];
        return -1;
    }

    self.pid = child;
    self.outFd = pfd[0];
    self.errFd = efd[0];
    self.startTime = [NSDate date];
    self.finished = NO;
    [self.outBuf setString:@""];
    [self.errBuf setString:@""];

    [self beginReading];
    return child;
}

- (void)beginReading {
    __weak typeof(self) weakSelf = self;
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_async(group, self.readQueue, ^{
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        [self pumpFd:self.outFd level:SPLogLevelOut buffer:self.outBuf];
    });
    dispatch_group_async(group, self.readQueue, ^{
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        [self pumpFd:self.errFd level:SPLogLevelErr buffer:self.errBuf];
    });

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        int status = 0;
        pid_t w = 0;
        // 子进程可能还没退出（读端 EOF ≈ 进程已关闭 fd，通常已退出）
        do { w = waitpid(self.pid, &status, 0); } while (w < 0 && errno == EINTR);
        int code = -1;
        if (w == self.pid) {
            if (WIFEXITED(status)) code = WEXITSTATUS(status);
            else if (WIFSIGNALED(status)) code = 128 + WTERMSIG(status);
        }
        self.pid = -1;
        [self completeWithExitCode:code];
    });

    // 超时处理
    if (self.timeout > 0) {
        NSTimeInterval t = self.timeout;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self && self.isRunning) { self.timedOut = YES; [self cancel]; }
        });
    }
}

- (void)pumpFd:(int)fd level:(SPLogLevel)level buffer:(NSMutableString *)buffer {
    char chunk[4096];
    NSMutableData *pending = [NSMutableData data];
    for (;;) {
        ssize_t n = read(fd, chunk, sizeof(chunk));
        if (n > 0) {
            [pending appendBytes:chunk length:(NSUInteger)n];
            // 按行切分
            const char *bytes = pending.bytes;
            NSUInteger start = 0;
            for (NSUInteger i = 0; i < pending.length; i++) {
                if (bytes[i] == '\n') {
                    NSData *lineData = [pending subdataWithRange:NSMakeRange(start, i - start)];
                    NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
                    if (!line) line = [[NSString alloc] initWithData:lineData encoding:NSISOLatin1StringEncoding];
                    [self emitLine:line ?: @"" level:level buffer:buffer];
                    start = i + 1;
                }
            }
            if (start > 0) [pending replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
            continue;
        }
        if (n == 0) break;
        if (errno == EINTR) continue;
        break;
    }
    if (pending.length) {
        NSString *tail = [[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding];
        if (!tail) tail = [[NSString alloc] initWithData:pending encoding:NSISOLatin1StringEncoding];
        [self emitLine:tail ?: @"" level:level buffer:buffer];
    }
    close(fd);
    if (fd == self.outFd) self.outFd = -1; else if (fd == self.errFd) self.errFd = -1;
}

- (void)emitLine:(NSString *)line level:(SPLogLevel)level buffer:(NSMutableString *)buffer {
    @synchronized (buffer) {
        [buffer appendString:line]; [buffer appendString:@"\n"];
        if (buffer.length > 4 * 1024 * 1024) { // 防止超大输出吃光内存
            [buffer deleteCharactersInRange:NSMakeRange(0, buffer.length - 2 * 1024 * 1024)];
        }
    }
    void (^cb)(NSString *, SPLogLevel) = self.onLine;
    if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(line, level); });
}

- (void)completeWithExitCode:(int)code {
    if (self.finished) return;
    self.finished = YES;
    SPCommandResult *r = self.result ?: [SPCommandResult new];
    r.exitCode = code;
    r.elapsed = -[self.startTime timeIntervalSinceNow];
    @synchronized (self.outBuf) { r.stdoutText = [self.outBuf copy]; }
    @synchronized (self.errBuf) { r.stderrText = [self.errBuf copy]; }
    r.cancelled = self.cancelRequested;
    r.timedOut = self.timedOut;
    if (!r.launchError && !r.cancelled && code != 0) {
        r.launchError = nil; // 非零退出不当作启动错误
    }
    self.result = r;
    [self finishNotifying];
}

- (void)finishNotifying {
    void (^cb)(SPCommandResult *) = self.onFinish;
    SPCommandResult *r = self.result;
    if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(r); });
}

#pragma mark 公开入口

- (int)runShell:(NSString *)script {
    NSString *sh = @"/bin/sh";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:sh]) sh = @"/var/jb/bin/sh";

    // posix_spawn 在 iOS 上没有可用的 chdir，改在脚本前面拼一句 cd；
    // exec 失败时 cd 也失败，脚本会立刻以非 0 退出，语义一样。
    NSString *body = script ?: @"";
    if (self.workingDirectory.length) {
        NSString *quoted = [self.workingDirectory stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        body = [NSString stringWithFormat:@"cd '%@' || exit 200\n%@", quoted, body];
    }
    return [self launch:sh args:@[@"-c", body]];
}

- (int)runExecutable:(NSString *)exe arguments:(NSArray<NSString *> *)args {
    return [self launch:exe args:args ?: @[]];
}

- (void)cancel {
    self.cancelRequested = YES;
    pid_t p = self.pid;
    if (p <= 0) return;
    // 整组终止：先 TERM 再 KILL
    kill(-p, SIGTERM);
    kill(p, SIGTERM);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        if (p > 0) { kill(-p, SIGKILL); kill(p, SIGKILL); }
    });
}

#pragma mark 同步便捷

+ (SPCommandResult *)runSyncShell:(NSString *)script
                      environment:(NSDictionary<NSString *, NSString *> *)env
                              cwd:(NSString *)cwd
                          timeout:(NSTimeInterval)timeout {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block SPCommandResult *res = nil;
    SPSession *s = [[SPSession alloc] initWithEnvironment:env workingDirectory:cwd];
    s.timeout = timeout;
    s.onFinish = ^(SPCommandResult *r) { res = r; dispatch_semaphore_signal(sem); };
    [s runShell:script];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return res ?: [SPCommandResult new];
}

@end
