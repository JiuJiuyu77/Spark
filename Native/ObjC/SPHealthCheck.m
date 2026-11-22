//
//  SPHealthCheck.m
//

#import "SPHealthCheck.h"
#import "SPCompat.h"
#import "SPToolchainInstaller.h"
#import "SPSession.h"

#pragma mark - 结果模型

@implementation SPHealthItem
- (BOOL)isFailure {
    return self.status == SPHealthStatusFail;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@>", self.title,
            @[@"pending",@"running",@"pass",@"warn",@"fail",@"skip"][MAX(0, MIN(5, self.status))]];
}
@end

@implementation SPHealthReport
- (NSInteger)countForStatus:(SPHealthStatus)status {
    NSInteger n = 0;
    for (SPHealthItem *i in self.items) if (i.status == status) n++;
    return n;
}
- (NSInteger)countForCategory:(SPHealthCategory)category {
    NSInteger n = 0;
    for (SPHealthItem *i in self.items) if (i.category == category) n++;
    return n;
}
- (NSArray<SPHealthItem *> *)itemsInCategory:(SPHealthCategory)category {
    NSMutableArray *out = [NSMutableArray array];
    for (SPHealthItem *i in self.items) if (i.category == category) [out addObject:i];
    return out;
}
- (BOOL)allPassed {
    for (SPHealthItem *i in self.items) {
        if (i.status == SPHealthStatusFail) return NO;
    }
    return YES;
}
- (NSString *)headline {
    NSInteger pass = [self countForStatus:SPHealthStatusPass];
    NSInteger warn = [self countForStatus:SPHealthStatusWarn];
    NSInteger fail = [self countForStatus:SPHealthStatusFail];
    if (fail) {
        return [NSString stringWithFormat:@"%ld 项未通过 · %ld 项警告 · %ld 项通过",
                (long)fail, (long)warn, (long)pass];
    }
    if (warn) {
        return [NSString stringWithFormat:@"全部可用 · %ld 项警告 · %ld 项通过",
                (long)warn, (long)pass];
    }
    return [NSString stringWithFormat:@"全部通过（%ld 项）", (long)pass];
}
@end

#pragma mark - 检查引擎

@interface SPHealthCheck ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSMutableArray<SPHealthItem *> *collected;
@end

@implementation SPHealthCheck

+ (NSString *)titleForCategory:(SPHealthCategory)c {
    switch (c) {
        case SPHealthCategoryRuntime:     return @"运行时";
        case SPHealthCategoryCompiler:    return @"编译链";
        case SPHealthCategoryToolchain:   return @"工具链";
        case SPHealthCategoryEnvironment: return @"环境";
        default: return @"";
    }
}

+ (NSString *)symbolForCategory:(SPHealthCategory)c {
    switch (c) {
        case SPHealthCategoryRuntime:     return @"shippingbox.fill";
        case SPHealthCategoryCompiler:    return @"hammer.fill";
        case SPHealthCategoryToolchain:   return @"wrench.and.screwdriver.fill";
        case SPHealthCategoryEnvironment: return @"gear.badge";
        default: return @"questionmark";
    }
}

#pragma mark - 说人话

/// 把常见报错翻译成「是什么 + 怎么办」。
/// 这张表是长期积累的，新增报错就往里加。
+ (nullable NSString *)humanizeOutput:(NSString *)output
                             exitCode:(NSInteger)exitCode
                               intent:(nullable NSString *)intent {
    NSString *o = output ?: @"";
    NSString *low = o.lowercaseString;

    // 找不到命令
    if ([low containsString:@"command not found"] || [low containsString:@"not found"]) {
        NSArray *tokens = [o componentsSeparatedByString:@"\\n"];
        NSString *which = nil;
        for (NSString *ln in tokens) {
            NSRange r = [ln rangeOfString:@"command not found"];
            if (r.location == NSNotFound) r = [ln rangeOfString:@"not found"];
            if (r.location == NSNotFound) continue;
            // 形如 "/bin/sh: line 1: clang: command not found"
            NSString *head = [ln substringToIndex:r.location];
            NSArray *segs = [head componentsSeparatedByString:@":"];
            if (segs.count >= 2) {
                which = [segs.lastObject stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];
            }
            if (which.length) break;
        }
        if (which.length) {
            return [NSString stringWithFormat:
                    @"找不到命令 `%@`。\n\n"
                     "原因通常是 PATH 没包含它所在的目录，或者工具链没展开完整。\n"
                     "下一步：到「工具」→「工具链」检查该项是否存在；"
                     "若刚展开过，退出重进本页再测。", which];
        }
        return @"有命令找不到。多半是 PATH 少了某个目录，或工具链未展开完整。";
    }

    // 链接失败
    if ([low containsString:@"undefined symbol"] || [low containsString:@"undefined reference"]) {
        return @"链接阶段找不到符号。\n\n"
                "常见原因：\n"
                " · 少了 -l 某个库（检查 Makefile 的 xxx_LIBRARIES）\n"
                " · 用了只在更高系统版本存在的 API，但没加 @available 判断\n"
                " · 源文件没加进 Makefile 的 xxx_FILES\n"
                "下一步：看日志里 undefined 后面的符号名，搜它的所属框架。";
    }
    if ([low containsString:@"ld: "]) {
        return @"链接器 ld64 报错。\n\n"
                "如果同时出现 library.mk 或 Error 2，真正的原因通常在更上面几行。\n"
                "下一步：在日志里搜 `ld: ` 往上找第一条，那才是根因。";
    }

    // SDK
    if ([low containsString:@"sdk"] && ([low containsString:@"not exist"] ||
                                        [low containsString:@"no such file"] ||
                                        [low containsString:@"does not exist"])) {
        return @"找不到 iOS SDK。\n\n"
                "Theos 只认 `$THEOS/sdks/iPhoneOS*.sdk`。\n"
                "下一步：到「工具」→「工具链」确认 SDK 那一项是勾，"
                "并确认里面有 SDKSettings.json（空目录不算）。";
    }

    // vendor
    if ([low containsString:@"vendor"]) {
        return @"Theos 的 vendor 目录没就绪。\n\n"
                "Theos 用 `vendor/include/.git` 和 `vendor/lib/.git` 判断 vendor 是否可用，"
                "缺了会报「vendor 目录缺失」但目录其实在。\n"
                "下一步：到「工具」→「工具链」重新展开内置工具链。";
    }

    // 权限
    if ([low containsString:@"permission denied"]) {
        return @"权限不足。\n\n"
                "要么目标文件不可写，要么可执行文件没有 x 位。\n"
                "下一步：确认工具链是从「工具链」页正常展开的；"
                "如果自己放过文件进去，检查权限。";
    }

    // 空间
    if ([low containsString:@"no space left"]) {
        return @"磁盘空间不足。\n\n"
                "下一步：删掉不需要的项目/日志，或在「设置」里清理旧构建产物。";
    }

    // posix_spawn
    if ([low containsString:@"posix_spawn"] || [low containsString:@"exec format"]) {
        return @"子进程无法启动。\n\n"
                "常见原因：\n"
                " · 运行时里的 shell 没打进 ipa（检查 helpers/bash）\n"
                " · 可执行文件架构不对（应为 arm64）\n"
                " · iOS 沙盒拒绝执行该路径下的二进制\n"
                "下一步：到「工具」→「工具链」重新展开运行时。";
    }

    // 通用兜底
    if (exitCode != 0) {
        NSString *first = nil;
        for (NSString *ln in [o componentsSeparatedByString:@"\\n"]) {
            NSString *t = [ln stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
            if (!t.length) continue;
            if ([t.lowercaseString containsString:@"error"] ||
                [t.lowercaseString containsString:@"fail"]) {
                first = t;
                break;
            }
        }
        if (first.length) {
            return [NSString stringWithFormat:
                    @"命令返回 %ld。第一条错误是：\n%@\n\n"
                     "上面「命令」一栏可以复制到终端里单独跑，方便逐步排查。",
                    (long)exitCode,
                    first.length > 300 ? [first substringToIndex:300] : first];
        }
        return [NSString stringWithFormat:@"命令返回 %ld，但没有明确的错误行。"
                "把「输出」展开看看。", (long)exitCode];
    }

    if (intent.length) return nil;
    return nil;
}

#pragma mark - 工具

/// 跑一条命令并把结果填进 item
- (void)run:(NSString *)script
       item:(SPHealthItem *)item
      intent:(NSString *)intent
   envPrefix:(nullable NSString *)envPrefix
    timeout:(NSTimeInterval)timeout {

    item.command = script;

    NSMutableString *full = [NSMutableString string];
    if (envPrefix.length) [full appendFormat:@"%@\\n", envPrefix];
    [full appendString:script];

    NSDate *t0 = [NSDate date];
    SPCommandResult *r = [SPSession runSyncShell:full
                                     environment:[[SPToolchainInstaller shared] runtimeEnvironment]
                                             cwd:NSTemporaryDirectory()
                                         timeout:timeout];
    item.elapsedMS = (NSInteger)(-[t0 timeIntervalSinceNow] * 1000);
    item.exitCode = r.exitCode;

    NSString *out = r.stdoutText ?: @"";
    NSString *err = r.stderrText ?: @"";
    NSString *merged = out.length && err.length
        ? [NSString stringWithFormat:@"%@\\n%@", out, err]
        : (out.length ? out : err);

    // 截断：保留头尾各 4000 字符，中间省略。
    // 编译日志动辄几 MB，全存进内存再塞进 cell 会直接卡死。
    const NSUInteger kLimit = 8000;
    if (merged.length > kLimit) {
        NSString *head = [merged substringToIndex:4000];
        NSString *tail = [merged substringFromIndex:merged.length - 3000];
        item.output = [NSString stringWithFormat:
                       @"%@\\n\\n… 省略 %lu 字符 …\\n\\n%@",
                       head, (unsigned long)(merged.length - 7000), tail];
    } else {
        item.output = merged;
    }

    if (r.launchError) {
        item.status = SPHealthStatusFail;
        item.summary = @"子进程启动失败";
        item.diagnosis = [NSString stringWithFormat:
                          @"无法启动子进程：%@\\n\\n"
                           "下一步：到「工具」→「工具链」确认运行时已展开，"
                           "且 helpers/bash 存在。",
                          r.launchError.localizedDescription ?: @"未知原因"];
        return;
    }

    if (r.timedOut) {
        item.status = SPHealthStatusFail;
        item.summary = [NSString stringWithFormat:@"超时（%.0f 秒）", timeout];
        item.diagnosis = @"命令超时未返回。\n\n"
                          "下一步：确认不是磁盘卡死或工具链路径指向网络盘。";
        return;
    }

    if (r.exitCode != 0) {
        item.status = SPHealthStatusFail;
        NSString *firstLine = [[out componentsSeparatedByString:@"\\n"] firstObject] ?: @"";
        item.summary = firstLine.length ? firstLine : [NSString stringWithFormat:@"返回 %ld", (long)r.exitCode];
        item.diagnosis = [SPHealthCheck humanizeOutput:merged exitCode:r.exitCode intent:intent];
        return;
    }

    item.status = SPHealthStatusPass;
    item.summary = [[out componentsSeparatedByString:@"\\n"] firstObject] ?: @"通过";
    // 去掉首尾空白，避免 cell 里出现空行
    item.summary = [item.summary stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!item.summary.length) item.summary = @"通过";
}

/// 纯文件存在性检查（不跑命令）
- (SPHealthItem *)fileItem:(SPHealthCategory)cat
                     title:(NSString *)title
                      path:(NSString *)path
                    isExec:(BOOL)isExec {
    SPHealthItem *it = [SPHealthItem new];
    it.category = cat;
    it.title = title;
    BOOL isDir = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir];
    if (!exists || isDir) {
        it.status = SPHealthStatusFail;
        it.summary = exists ? @"是个目录" : @"不存在";
        it.output = path;
        it.diagnosis = [NSString stringWithFormat:
                        @"%@\n\n这个文件应该在工具链里。"
                         "下一步：到「工具」→「工具链」重新展开内置工具链。",
                        path];
        return it;
    }
    if (isExec && ![NSFileManager.defaultManager isExecutableFileAtPath:path]) {
        it.status = SPHealthStatusFail;
        it.summary = @"没有可执行权限";
        it.output = path;
        it.diagnosis = @"文件在，但缺 x 位。\n\n"
                        "下一步：重新展开工具链（正常展开会自动设置权限）。";
        return it;
    }
    it.status = SPHealthStatusPass;
    it.summary = [path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
    return it;
}

#pragma mark - 主流程

- (void)runWithItemUpdate:(void (^)(SPHealthItem *))itemUpdate
               completion:(void (^)(SPHealthReport *))completion {
    [self runCategories:nil itemUpdate:itemUpdate completion:completion];
}

- (void)runCategories:(NSArray<NSNumber *> *)categories
           itemUpdate:(void (^)(SPHealthItem *))itemUpdate
           completion:(void (^)(SPHealthReport *))completion {
    if (self.running) return;
    self.running = YES;
    self.collected = [NSMutableArray array];

    NSDate *start = [NSDate date];

    void (^emit)(SPHealthItem *) = ^(SPHealthItem *it) {
        @synchronized (self.collected) { [self.collected addObject:it]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (itemUpdate) itemUpdate(it);
        });
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL (^wanted)(SPHealthCategory) = ^BOOL(SPHealthCategory c) {
            if (!categories.count) return YES;
            for (NSNumber *n in categories) if (n.integerValue == c) return YES;
            return NO;
        };

        if (wanted(SPHealthCategoryRuntime))     [self checkRuntime:emit];
        if (wanted(SPHealthCategoryCompiler))    [self checkCompiler:emit];
        if (wanted(SPHealthCategoryToolchain))   [self checkToolchain:emit];
        if (wanted(SPHealthCategoryEnvironment)) [self checkEnvironment:emit];

        SPHealthReport *rep = [SPHealthReport new];
        @synchronized (self.collected) { rep.items = [self.collected copy]; }
        rep.startedAt = start;
        rep.totalSeconds = -[start timeIntervalSinceNow];
        self.running = NO;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(rep);
        });
    });
}

#pragma mark - 运行时

- (void)checkRuntime:(void (^)(SPHealthItem *))emit {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    NSFileManager *fm = NSFileManager.defaultManager;

    // 1. shell 是否存在
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryRuntime;
        it.title = @"shell 可执行文件";
        NSString *sh = [SPSession resolveShell];
        if (!sh.length) {
            it.status = SPHealthStatusFail;
            it.summary = @"找不到";
            it.diagnosis = @"运行时里没有可用的 shell。\n\n"
                            "下一步：到「工具」→「工具链」展开内置运行时。";
        } else {
            it.status = SPHealthStatusPass;
            it.summary = [sh stringByReplacingOccurrencesOfString:NSHomeDirectory()
                                                        withString:@"~"];
        }
        it.output = sh;
        emit(it);
    }

    // 2. shell 能否真的启动（这一步才暴露 posix_spawn 被拒）
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryRuntime;
        it.title = @"shell 能启动";
        [self run:@"echo spark-shell-ok" item:it
           intent:@"验证子进程能起来" envPrefix:nil timeout:20];
        if (it.status == SPHealthStatusPass) {
            it.summary = @"echo 正常返回";
            it.diagnosis = nil;
        }
        emit(it);
    }

    // 3. 临时目录可写
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryRuntime;
        it.title = @"临时目录可写";
        NSString *tmp = NSTemporaryDirectory();
        NSString *probe = [tmp stringByAppendingPathComponent:@"spark-health-probe"];
        NSError *err = nil;
        BOOL ok = [@"probe" writeToFile:probe atomically:YES
                               encoding:NSUTF8StringEncoding error:&err];
        [fm removeItemAtPath:probe error:NULL];
        it.status = ok ? SPHealthStatusPass : SPHealthStatusFail;
        it.summary = ok ? tmp : (err.localizedDescription ?: @"写入失败");
        it.output = tmp;
        if (!ok) {
            it.diagnosis = @"临时目录不可写，编译产物无处存放。\n\n"
                            "下一步：重启 App；若仍不行，检查设备剩余空间。";
        }
        emit(it);
    }

    // 4. helpers 目录
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryRuntime;
        it.title = @"helpers 目录";
        NSString *h = [inst.installRoot stringByAppendingPathComponent:@"helpers"];
        BOOL isDir = NO;
        BOOL ok = [fm fileExistsAtPath:h isDirectory:&isDir] && isDir;
        NSInteger n = ok ? (NSInteger)([fm contentsOfDirectoryAtPath:h error:NULL] ?: @[]).count : 0;
        it.status = ok && n > 0 ? SPHealthStatusPass : SPHealthStatusFail;
        it.summary = ok ? [NSString stringWithFormat:@"%ld 个文件", (long)n] : @"不存在";
        it.output = h;
        if (!(ok && n > 0)) {
            it.diagnosis = @"helpers 里放着 bash、dpkg-deb、fakeroot 等打包必需的工具。\n\n"
                            "下一步：到「工具」→「工具链」重新展开运行时。";
        }
        emit(it);
    }

    // 5. 磁盘空间
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryRuntime;
        it.title = @"可用磁盘空间";
        // 注意：ObjC 字符串里不能再出现未转义的 "，
        // 所以 awk 只输出数字，单位在下面拼。
        [self run:@"df -Pm . 2>/dev/null | awk 'NR==2{print $4}'"
              item:it intent:@"检查剩余空间" envPrefix:nil timeout:15];
        if (it.status == SPHealthStatusPass) {
            // awk 现在只输出数字（没有单位），直接取值
            NSInteger mb = it.summary.integerValue;
            if (mb > 0 && mb < 200) {
                it.status = SPHealthStatusWarn;
                it.summary = [NSString stringWithFormat:@"仅剩 %ld MB", (long)mb];
                it.diagnosis = @"空间偏少。\n\n"
                                "编译 iOS 工程加上 SDK 需要数百 MB 临时空间，"
                                "空间不足会导致链接阶段莫名失败。";
            } else if (mb > 0) {
                it.summary = [NSString stringWithFormat:@"%ld MB 可用", (long)mb];
            }
        }
        emit(it);
    }
}

#pragma mark - 编译链

- (void)checkCompiler:(void (^)(SPHealthItem *))emit {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];

    // 关键工具清单（缺任何一个都会在中途以难懂的方式失败）
    NSArray *tools = @[@"clang", @"clang++", @"ld64", @"ldid", @"make", @"strip", @"ar", @"dpkg-deb"];
    for (NSString *t in tools) {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryCompiler;
        it.title = t;

        // 依次在这些目录里找。**必须覆盖 theos-root/ 布局** ——
        // 当前运行时是 Rein 对齐包：真正的 clang 在
        // theos-root/usr/lib/llvm-16/bin，基础命令在 theos-root/usr/bin。
        // 之前只查 installRoot/usr/lib/llvm-16/bin（不存在），
        // 于是 clang / clang++ 一律报「找不到」。
        NSString *root = inst.installRoot;
        NSArray *dirs = @[
            [root stringByAppendingPathComponent:@"usr/lib/llvm-16/bin"],
            [root stringByAppendingPathComponent:@"theos-root/usr/lib/llvm-16/bin"],
            inst.binDir ?: @"",
            [root stringByAppendingPathComponent:@"theos-root/usr/bin"],
            inst.baseBinDir ?: @"",
            [root stringByAppendingPathComponent:@"helpers"],
            [root stringByAppendingPathComponent:@"bin"],
            [root stringByAppendingPathComponent:@"usr/bin"],
        ];
        // usr/bin 里只有 clang-16 / clang++-16，Theos 调的是 clang / clang++。
        // 这里把别名也算命中，否则明明能编译却报「找不到 clang」。
        NSMutableArray *names = [NSMutableArray arrayWithObject:t];
        if ([t isEqualToString:@"clang"]) [names addObject:@"clang-16"];
        if ([t isEqualToString:@"clang++"]) [names addObject:@"clang++-16"];

        NSString *found = nil;
        for (NSString *d in dirs) {
            if (!d.length) continue;
            for (NSString *n in names) {
                NSString *p = [d stringByAppendingPathComponent:n];
                if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) { found = p; break; }
            }
            if (found) break;
        }
        if (found) {
            it.status = SPHealthStatusPass;
            it.summary = [found stringByReplacingOccurrencesOfString:NSHomeDirectory()
                                                           withString:@"~"];
            if (![[found lastPathComponent] isEqualToString:t]) {
                it.summary = [NSString stringWithFormat:@"%@（实为 %@）",
                              it.summary, [found lastPathComponent]];
            }
            it.output = found;
        } else {
            it.status = SPHealthStatusFail;
            it.summary = @"找不到";
            it.output = [dirs componentsJoinedByString:@"\n"];
            it.diagnosis = [NSString stringWithFormat:
                            @"在以下目录里都没找到可执行的 %@：\n%@\n\n"
                             "下一步：到「工具」→「工具链」重新展开。",
                            t, it.output];
        }
        emit(it);
    }

    // ld64 的动态库依赖
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryCompiler;
        it.title = @"ld64 依赖库";
        NSArray *deps = @[@"libxar.1.dylib", @"libtapi.dylib"];
        NSMutableArray *miss = [NSMutableArray array];
        for (NSString *d in deps) {
            NSString *p = [inst.libDir stringByAppendingPathComponent:d];
            if (![NSFileManager.defaultManager fileExistsAtPath:p]) [miss addObject:d];
        }
        it.status = miss.count ? SPHealthStatusFail : SPHealthStatusPass;
        it.summary = miss.count ? [NSString stringWithFormat:@"缺 %@", [miss componentsJoinedByString:@"、"]]
                                : @"libxar + libtapi 就绪";
        it.output = inst.libDir;
        if (miss.count) {
            it.diagnosis = @"ld64 依赖这两个库。缺了以后链接只会报一句 "
                            "「library.mk:37 Error 2」，完全看不出是缺库。\n\n"
                            "下一步：到「工具」→「工具链」重新展开。";
        }
        emit(it);
    }

    // clang 真实版本（能跑起来才算数）
    {
        it.title = @"clang 可运行";
        // 与上面工具查找保持同一套目录：当前运行时是 Rein 对齐包，
        // 真正的 clang 在 theos-root/usr/lib/llvm-16/bin。
        NSString *root = inst.installRoot;
        NSArray *clangCands = @[
            [root stringByAppendingPathComponent:@"usr/lib/llvm-16/bin/clang"],
            [root stringByAppendingPathComponent:@"theos-root/usr/lib/llvm-16/bin/clang"],
            [inst.binDir stringByAppendingPathComponent:@"clang"],
            [inst.binDir stringByAppendingPathComponent:@"clang-16"],
            [root stringByAppendingPathComponent:@"theos-root/usr/bin/clang-16"],
            [root stringByAppendingPathComponent:@"usr/bin/clang"],
            [root stringByAppendingPathComponent:@"usr/bin/clang-16"],
        ];
        NSString *clangPath = nil;
        for (NSString *p in clangCands) {
            if (p.length && [NSFileManager.defaultManager isExecutableFileAtPath:p]) {
                clangPath = p; break;
            }
        }
        if (!clangPath) {
            it.status = SPHealthStatusSkip;
            it.summary = @"跳过（clang 不存在）";
            it.output = [clangCands componentsJoinedByString:@"\n"];
            emit(it);
            return;
        }
        // PATH / DYLD 已由 runtimeEnvironment 统一提供，
        // 这里只把 clang 所在目录顶到最前，保证它自己能被解析到。
        NSString *env = [NSString stringWithFormat:@"export PATH=%@:$PATH",
                         [SPUtil shellQuote:[clangPath stringByDeletingLastPathComponent]]];
        NSString *cmd = [NSString stringWithFormat:@"%@ --version 2>&1 | head -2",
                         [SPUtil shellQuote:clangPath]];
        [self run:cmd item:it intent:@"确认 clang 能跑" envPrefix:env timeout:20];
        if (it.status == SPHealthStatusPass) {
            NSString *one = [it.summary stringByReplacingOccurrencesOfString:@"\n"
                                                                  withString:@" "];
            it.summary = [NSString stringWithFormat:@"%@ · %@", one, [clangPath lastPathComponent]];
        }
        emit(it);
    }
}

#pragma mark - 工具链

- (void)checkToolchain:(void (^)(SPHealthItem *))emit {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *theos = inst.theosPath;

    // Theos 根目录定位（运行时里可能是 theos-root/theos 布局）
    if (!theos.length || ![fm fileExistsAtPath:[theos stringByAppendingPathComponent:@"makefiles/common.mk"]]) {
        NSString *alt = [inst.installRoot stringByAppendingPathComponent:@"theos-root/theos"];
        if ([fm fileExistsAtPath:[alt stringByAppendingPathComponent:@"makefiles/common.mk"]]) {
            theos = alt;
        }
    }

    // 1. makefiles
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryToolchain;
        it.title = @"Theos makefiles";
        NSString *p = [theos stringByAppendingPathComponent:@"makefiles/common.mk"];
        BOOL ok = [fm fileExistsAtPath:p];
        it.status = ok ? SPHealthStatusPass : SPHealthStatusFail;
        it.summary = ok ? [theos stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]
                        : @"缺 makefiles/common.mk";
        it.output = theos ?: @"(路径为空)";
        if (!ok) {
            it.diagnosis = @"找不到 Theos 的核心 makefile。\n\n"
                            "下一步：到「工具」→「工具链」重新展开（会同时修复下面几项）。";
        }
        emit(it);
    }

    // 2. logos.pl
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryToolchain;
        it.title = @"Logos 预处理器";
        NSArray *cands = @[
            [theos stringByAppendingPathComponent:@"bin/logos.pl"],
            [inst.installRoot stringByAppendingPathComponent:@"theos/bin/logos.pl"],
            [inst.installRoot stringByAppendingPathComponent:@"theos-root/theos/bin/logos.pl"],
        ];
        NSString *found = nil;
        for (NSString *c in cands) if ([fm fileExistsAtPath:c]) { found = c; break; }
        it.status = found ? SPHealthStatusPass : SPHealthStatusFail;
        it.summary = found ? [found stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]
                           : @"找不到 logos.pl";
        it.output = [cands componentsJoinedByString:@"\n"];
        if (!found) {
            it.diagnosis = @"没有 Logos 预处理器，.x 文件无法展开成 .m，"
                            "含 %hook 的工程一定编译失败。\n\n"
                            "下一步：到「工具」→「工具链」重新展开。";
        }
        emit(it);
    }

    // 3. vendor 标记（Theos 用它判断 vendor 是否就绪）
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryToolchain;
        it.title = @"vendor 标记";
        NSString *vi = [theos stringByAppendingPathComponent:@"vendor/include/.git"];
        NSString *vl = [theos stringByAppendingPathComponent:@"vendor/lib/.git"];
        BOOL a = [fm fileExistsAtPath:vi];
        BOOL b = [fm fileExistsAtPath:vl];
        it.status = (a && b) ? SPHealthStatusPass : SPHealthStatusFail;
        it.summary = [NSString stringWithFormat:@"include:%@ lib:%@",
                      a ? @"✓" : @"✗", b ? @"✓" : @"✗"];
        it.output = [NSString stringWithFormat:@"%@\n%@", vi, vl];
        if (!(a && b)) {
            it.diagnosis = @"Theos 用 vendor/*/.git 判断 vendor 是否就绪，"
                            "缺了会报「vendor 目录缺失」但目录其实在。\n\n"
                            "下一步：到「工具」→「工具链」重新展开。";
        }
        emit(it);
    }

    // 4. SDK —— 两处都查：$THEOS/sdks 和运行时顶层 sdks/
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryToolchain;
        it.title = @"iPhoneOS SDK";

        NSMutableArray *found = [NSMutableArray array];
        NSMutableArray *broken = [NSMutableArray array];
        NSArray *dirs = @[
            [theos stringByAppendingPathComponent:@"sdks"],
            [inst.installRoot stringByAppendingPathComponent:@"sdks"],
        ];
        for (NSString *d in dirs) {
            for (NSString *n in [fm contentsOfDirectoryAtPath:d error:NULL] ?: @[]) {
                if (![n hasPrefix:@"iPhoneOS"] || ![n hasSuffix:@".sdk"]) continue;
                NSString *sd = [d stringByAppendingPathComponent:n];
                // 完整性：三件套都在才算完整
                BOOL settings = [fm fileExistsAtPath:[sd stringByAppendingPathComponent:@"SDKSettings.json"]];
                BOOL inc = [fm fileExistsAtPath:[sd stringByAppendingPathComponent:@"usr/include"]];
                BOOL fw = [fm fileExistsAtPath:[sd stringByAppendingPathComponent:@"System/Library/Frameworks"]];
                if (settings && inc && fw) {
                    if (![found containsObject:n]) [found addObject:n];
                } else {
                    NSString *miss = settings ? (inc ? @"Frameworks" : @"usr/include") : @"SDKSettings.json";
                    [broken addObject:[NSString stringWithFormat:@"%@（缺 %@）", n, miss]];
                }
            }
        }

        if (found.count) {
            it.status = broken.count ? SPHealthStatusWarn : SPHealthStatusPass;
            it.summary = [found componentsJoinedByString:@", "];
            if (broken.count) {
                it.summary = [NSString stringWithFormat:@"%@（另有 %lu 个不完整）",
                              it.summary, (unsigned long)broken.count];
            }
        } else {
            it.status = SPHealthStatusFail;
            it.summary = broken.count ? @"只有不完整的 SDK" : @"一个都没有";
        }
        it.output = [[dirs componentsJoinedByString:@"\n"] stringByAppendingFormat:@"\n\n完整：%@\n不完整：%@",
                     [found componentsJoinedByString:@"、"] ?: @"无",
                     [broken componentsJoinedByString:@"、"]];

        if (it.status == SPHealthStatusFail) {
            it.diagnosis = @"Theos 只认 `$THEOS/sdks/iPhoneOS*.sdk`，而且要求：\n"
                            " · SDKSettings.json 在\n"
                            " · usr/include 在\n"
                            " · System/Library/Frameworks 非空\n\n"
                            "只有 SDKSettings.json 的半成品不算（复制中途失败会留下这种）。\n"
                            "下一步：到「工具」→「工具链」重新展开。";
        } else if (broken.count) {
            it.diagnosis = [NSString stringWithFormat:
                            @"这些 SDK 目录不完整，编译时会被跳过或直接报错：\n%@\n\n"
                             "下一步：到「工具」→「工具链」重新展开，会自动清理残件并重拷。",
                            [broken componentsJoinedByString:@"\n"]];
        }
        emit(it);
    }

    // 5. Theos 版本（能跑 make --version 更好，但先看目录结构）
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryToolchain;
        it.title = @"Theos 结构完整";
        NSArray *need = @[@"makefiles/common.mk", @"makefiles/instance/rules.mk",
                          @"makefiles/package/deb.mk", @"makefiles/targets/_common/darwin_head.mk"];
        NSMutableArray *miss = [NSMutableArray array];
        for (NSString *n in need) {
            if (![fm fileExistsAtPath:[theos stringByAppendingPathComponent:n]]) [miss addObject:n];
        }
        it.status = miss.count ? SPHealthStatusFail : SPHealthStatusPass;
        it.summary = miss.count ? [NSString stringWithFormat:@"缺 %lu 个关键文件", (unsigned long)miss.count]
                                : @"4/4 关键文件就绪";
        it.output = miss.count ? [miss componentsJoinedByString:@"\n"] : theos;
        if (miss.count) {
            it.diagnosis = [NSString stringWithFormat:
                            @"Theos 安装不完整，缺：\n%@\n\n"
                             "特别是 targets/_common/darwin_head.mk —— 没有它，"
                             "make 根本不知道用什么编译器，会直接失败。\n"
                             "下一步：到「工具」→「工具链」重新展开。",
                            [miss componentsJoinedByString:@"\n"]];
        }
        emit(it);
    }
}

#pragma mark - 环境

- (void)checkEnvironment:(void (^)(SPHealthItem *))emit {
    SPToolchainInstaller *inst = [SPToolchainInstaller shared];

    // 1. 进程身份（只是信息，不是通过条件）
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryEnvironment;
        it.title = @"进程身份";
        uid_t uid = getuid();
        it.status = SPHealthStatusPass;
        it.summary = [NSString stringWithFormat:@"uid=%d（%@）", (int)uid,
                      uid == 0 ? @"root" : @"mobile"];
        it.output = [NSString stringWithFormat:@"euid=%d ruid=%d gid=%d",
                     (int)geteuid(), (int)getuid(), (int)getgid()];
        if (uid != 0) {
            it.diagnosis = @"不是 root —— 但这**不必然**导致失败。\n\n"
                            "编译全在 App 包内进行（工具/SDK 都在包里），"
                            "产物写到 Documents 下，都不需要 root。\n"
                            "如果构建失败，看「编译链」和「工具链」那几项。";
        }
        emit(it);
    }

    // 2. 子进程身份（这个才真正决定能不能写系统路径）
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryEnvironment;
        it.title = @"子进程身份";
        NSString *probe =
            @"echo uid=${EUID:-$UID}; "
             "touch /usr/lib/.spark-probe 2>/dev/null && "
             "{ echo syswrite=yes; rm -f /usr/lib/.spark-probe; } || echo syswrite=no";
        [self run:probe item:it intent:@"探测子进程权限" envPrefix:nil timeout:15];
        if (it.status == SPHealthStatusPass) {
            BOOL sysWrite = [it.output containsString:@"syswrite=yes"];
            NSString *uidLine = [[it.output componentsSeparatedByString:@"\n"] firstObject] ?: @"";
            it.summary = [NSString stringWithFormat:@"%@ · 系统路径%@",
                          uidLine, sysWrite ? @"可写" : @"只读"];
            it.status = SPHealthStatusPass;
            if (!sysWrite) {
                it.diagnosis = @"子进程写不了系统路径。\n\n"
                                "基础编译仍可完成（产物在 Documents 下）。"
                                "只有当你要直接安装到系统目录时才会受影响。";
            }
        }
        emit(it);
    }

    // 3. PATH 是否包含关键目录
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryEnvironment;
        it.title = @"PATH 关键目录";
        NSArray *need = @[
            [inst.installRoot stringByAppendingPathComponent:@"usr/lib/llvm-16/bin"],
            [inst.installRoot stringByAppendingPathComponent:@"usr/bin"],
            [inst.installRoot stringByAppendingPathComponent:@"helpers"],
        ];
        NSMutableArray *miss = [NSMutableArray array];
        for (NSString *d in need) {
            if (![NSFileManager.defaultManager fileExistsAtPath:d]) [miss addObject:d];
        }
        it.status = miss.count ? SPHealthStatusWarn : SPHealthStatusPass;
        it.summary = miss.count ? [NSString stringWithFormat:@"%lu 个目录不存在", (unsigned long)miss.count]
                                : @"3/3 目录就绪";
        it.output = [need componentsJoinedByString:@"\n"];
        if (miss.count) {
            it.diagnosis = [NSString stringWithFormat:
                            @"这些目录不存在：\n%@\n\n"
                             "编译时会把它们拼进 PATH，不存在本身不报错，"
                             "但里面本该有的工具就找不到了。\n"
                             "下一步：到「工具」→「工具链」重新展开。",
                            [miss componentsJoinedByString:@"\n"]];
        }
        emit(it);
    }

    // 4. 架构
    {
        SPHealthItem *it = [SPHealthItem new];
        it.category = SPHealthCategoryEnvironment;
        it.title = @"本机架构";
        [self run:@"uname -m" item:it intent:@"确认架构" envPrefix:nil timeout:10];
        if (it.status == SPHealthStatusPass) {
            if (![it.summary containsString:@"arm64"]) {
                it.status = SPHealthStatusWarn;
                it.diagnosis = @"不是 arm64。\n\n"
                                "工具链里的二进制都是 arm64，架构不符时"
                                "子进程会以「exec format error」失败。";
            }
        }
        emit(it);
    }
}

@end