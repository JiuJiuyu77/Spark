//
//  SPCrashAnalysis.m
//

#import "SPCrashAnalysis.h"
#import "SPCompat.h"

@implementation SPCrashFrame
@end
@implementation SPCrashFinding
@end
@implementation SPCrashReport
@end

@implementation SPCrashAnalysis

#pragma mark - 解析入口

+ (SPCrashReport *)analyzePath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        if (error) *error = SPError(SPErrorCodeIO, @"读不到崩溃文件");
        return nil;
    }
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!raw) raw = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!raw.length) {
        if (error) *error = SPError(SPErrorCodeIO, @"编码无法识别");
        return nil;
    }

    SPCrashReport *report = [SPCrashReport new];
    report.path = path;

    // .ips：第一行是 JSON 头，其余是 JSON 体；也可能整体是单个 JSON
    NSRange nl = [raw rangeOfString:@"\n"];
    BOOL parsed = NO;
    if (nl.location != NSNotFound) {
        NSString *head = [raw substringToIndex:nl.location];
        NSString *body = [raw substringFromIndex:nl.location + 1];
        NSData *hd = [head dataUsingEncoding:NSUTF8StringEncoding];
        NSData *bd = [body dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *h = hd ? [NSJSONSerialization JSONObjectWithData:hd options:0 error:NULL] : nil;
        NSDictionary *b = bd ? [NSJSONSerialization JSONObjectWithData:bd options:0 error:NULL] : nil;
        if ([h isKindOfClass:NSDictionary.class] && [b isKindOfClass:NSDictionary.class]) {
            [self fillReport:report header:h body:b];
            parsed = YES;
        }
    }
    if (!parsed) {
        NSData *all = [raw dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *j = all ? [NSJSONSerialization JSONObjectWithData:all options:0 error:NULL] : nil;
        if ([j isKindOfClass:NSDictionary.class]) {
            [self fillReport:report header:j body:j];
            parsed = YES;
        }
    }
    if (!parsed) {
        // 老式文本 .crash：逐行找关键字
        [self parseLegacyText:raw into:report];
    }

    report.findings = [self findingsForReport:report];
    report.summary = [self summaryForReport:report];
    report.plainText = [self markdownForReport:report];
    return report;
}

+ (void)fillReport:(SPCrashReport *)r header:(NSDictionary *)h body:(NSDictionary *)b {
    r.appName = h[@"app_name"] ?: b[@"procName"] ?: @"";
    r.bundleId = h[@"bundleID"] ?: ([b[@"bundleInfo"] isKindOfClass:NSDictionary.class] ? b[@"bundleInfo"][@"CFBundleIdentifier"] : nil) ?: @"";
    r.version = h[@"app_version"] ?: @"";
    r.osVersion = h[@"os_version"] ?: ([b[@"osVersion"] isKindOfClass:NSDictionary.class] ? b[@"osVersion"][@"train"] : nil) ?: @"";
    r.device = b[@"modelCode"] ?: @"";

    NSString *ts = h[@"timestamp"] ?: b[@"captureTime"];
    if ([ts isKindOfClass:NSString.class] && ts.length) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyy-MM-dd HH:mm:ss.SS Z";
        NSDate *d = [f dateFromString:ts];
        if (!d) { f.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSSZ"; d = [f dateFromString:ts]; }
        r.crashTime = d;
    }

    // 异常
    NSDictionary *exc = [b[@"exception"] isKindOfClass:NSDictionary.class] ? b[@"exception"] : nil;
    r.exceptionType = exc[@"type"] ?: @"";
    r.signal = exc[@"signal"] ?: @"";
    NSDictionary *term = [b[@"termination"] isKindOfClass:NSDictionary.class] ? b[@"termination"] : nil;
    if (term) {
        NSString *ind = term[@"indicator"] ?: @"";
        NSString *ns = term[@"namespace"] ?: @"";
        r.termination = [NSString stringWithFormat:@"%@ %@ %@", ns, ind, term[@"code"] ?: @""].copy;
        r.termination = [r.termination stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }

    // asi（附加信息），例如 "abort() called"
    NSDictionary *asi = [b[@"asi"] isKindOfClass:NSDictionary.class] ? b[@"asi"] : nil;
    if (!r.termination.length && asi) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *k in asi) {
            id v = asi[k];
            if ([v isKindOfClass:NSArray.class]) [parts addObjectsFromArray:v];
            else if ([v isKindOfClass:NSString.class]) [parts addObject:v];
        }
        r.termination = [parts componentsJoinedByString:@"; "];
    }

    // 图像表
    NSMutableArray *images = [NSMutableArray array];
    for (NSDictionary *img in (b[@"usedImages"] ?: @[])) {
        if (![img isKindOfClass:NSDictionary.class]) continue;
        NSString *name = img[@"name"];
        if (!name.length) name = [img[@"path"] lastPathComponent];
        [images addObject:name ?: @"?"];
    }

    // 触发线程
    NSArray *threads = b[@"threads"] ?: @[];
    NSDictionary *trigger = nil;
    for (NSDictionary *t in threads) {
        if ([t isKindOfClass:NSDictionary.class] && [t[@"triggered"] boolValue]) { trigger = t; break; }
    }
    if (!trigger && threads.count) trigger = threads.firstObject;
    if (trigger) {
        r.triggeredThread = trigger[@"name"] ?: trigger[@"queue"] ?: @"(未命名线程)";
        NSMutableArray *frames = [NSMutableArray array];
        NSInteger idx = 0;
        for (NSDictionary *fr in (trigger[@"frames"] ?: @[])) {
            if (idx++ > 40) break;
            SPCrashFrame *f = [SPCrashFrame new];
            NSInteger ii = [fr[@"imageIndex"] integerValue];
            f.image = (ii >= 0 && ii < (NSInteger)images.count) ? images[ii] : @"?";
            f.symbol = fr[@"symbol"] ?: @"";
            f.offset = [fr[@"imageOffset"] unsignedLongLongValue];
            [frames addObject:f];
        }
        r.frames = frames;
    }

    // 未捕获异常的回溯（更精确）
    NSArray *leb = b[@"lastExceptionBacktrace"];
    if ([leb isKindOfClass:NSArray.class] && leb.count) {
        NSMutableArray *frames = [NSMutableArray array];
        for (NSDictionary *fr in leb) {
            if (![fr isKindOfClass:NSDictionary.class]) continue;
            SPCrashFrame *f = [SPCrashFrame new];
            NSInteger ii = [fr[@"imageIndex"] integerValue];
            f.image = (ii >= 0 && ii < (NSInteger)images.count) ? images[ii] : @"?";
            f.symbol = fr[@"symbol"] ?: @"";
            f.offset = [fr[@"imageOffset"] unsignedLongLongValue];
            [frames addObject:f];
        }
        r.frames = frames;   // 用异常回溯覆盖
        r.exceptionType = r.exceptionType.length ? r.exceptionType : @"NSException";
    }
}

+ (void)parseLegacyText:(NSString *)text into:(SPCrashReport *)r {
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([t hasPrefix:@"Exception Type:"]) r.exceptionType = [t substringFromIndex:15];
        else if ([t hasPrefix:@"Termination Reason:"]) r.termination = [t substringFromIndex:19];
        else if ([t hasPrefix:@"OS Version:"]) r.osVersion = [t substringFromIndex:11];
        else if ([t hasPrefix:@"Process:"]) r.appName = [t substringFromIndex:8];
    }
    r.exceptionType = [r.exceptionType stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

#pragma mark - 规则识别

+ (NSArray<SPCrashFinding *> *)findingsForReport:(SPCrashReport *)r {
    NSMutableArray<SPCrashFinding *> *out = [NSMutableArray array];
    NSString *exc = r.exceptionType.uppercaseString ?: @"";
    NSString *term = r.termination ?: @"";
    NSString *termLower = term.lowercaseString;

    void (^add)(SPCrashSeverity, NSString *, NSString *, NSString *) =
    ^(SPCrashSeverity sev, NSString *title, NSString *detail, NSString *sug) {
        SPCrashFinding *f = [SPCrashFinding new];
        f.severity = sev; f.title = title; f.detail = detail; f.suggestion = sug;
        [out addObject:f];
    };

    // 1. 野指针 / 访问已释放对象
    if ([exc containsString:@"BAD_ACCESS"] || [r.signal isEqualToString:@"SIGSEGV"] || [r.signal isEqualToString:@"SIGBUS"]) {
        NSString *addr = @"";
        for (SPCrashFrame *f in r.frames) {
            if (f.symbol.length && ![f.image hasPrefix:@"libsystem"]) { addr = f.symbol; break; }
        }
        add(SPCrashSeverityError, @"野指针 / 非法内存访问",
            [NSString stringWithFormat:@"%@（%@）通常意味着访问了已释放的对象，或数组越界。%@",
             r.exceptionType ?: @"EXC_BAD_ACCESS", r.signal ?: @"",
             addr.length ? [NSString stringWithFormat:@"最上层业务帧：%@", addr] : @""],
            @"检查 ARC 下 __unsafe_unretained / assign 的代理属性；weak 对象在回调里要先判空；"
             @"数组用 objectAtIndex 前确认 index < count。");
    }

    // 2. 未捕获 ObjC 异常（abort）
    BOOL hasExceptionFrames = NO;
    for (SPCrashFrame *f in r.frames) {
        if ([f.symbol containsString:@"exceptionPreprocess"] ||
            [f.symbol containsString:@"objc_exception_throw"]) { hasExceptionFrames = YES; break; }
    }
    if (hasExceptionFrames || [termLower containsString:@"abort"]) {
        add(SPCrashSeverityError, @"未捕获的 Objective-C 异常",
            [NSString stringWithFormat:@"进程被 abort() 终止。%@", term.length ? term : @""],
            @"找日志里的 \"*** Terminating app due to uncaught exception\" 一行，"
             @"看 NSException 名字（如 NSInvalidArgumentException）和 reason。");
    }

    // 3. 栈溢出
    if ([exc containsString:@"STACK_OVERFLOW"] ||
        [r.signal isEqualToString:@"SIGSEGV"] && [r.frames.firstObject.symbol containsString:@"recursive"]) {
        add(SPCrashSeverityError, @"栈溢出（递归过深）", @"典型是无限递归或超大局部变量。",
            @"检查递归终止条件；避免在栈上分配大数组（>几 MB）。");
    }

    // 4. 看门狗 / 卡死
    if ([exc containsString:@"WATCHDOG"] || [termLower containsString:@"0x8badf00d"]) {
        add(SPCrashSeverityError, @"主线程卡死（看门狗超时）",
            @"0x8badf00d = watchdog 判定启动或响应超时。",
            @"把所有网络/文件/磁盘操作移到后台队列；启动阶段别在主线程做大循环。");
    }

    // 5. 内存不足
    if ([termLower containsString:@"0xdead10cc"] || [termLower containsString:@"jetsam"] ||
        [exc containsString:@"MEMORY"]) {
        add(SPCrashSeverityError, @"内存不足被系统杀掉",
            @"jetsam / 0xdead10cc 表示系统回收了进程。",
            @"查图片解码缓存与日志缓冲上限；大文件分块处理。");
    }

    // 6. 常见 ObjC 异常关键字
    NSString *all = [[NSString stringWithFormat:@"%@ %@", r.termination ?: @"", r.summary ?: @""] lowercaseString];
    for (SPCrashFrame *f in r.frames) {
        all = [all stringByAppendingFormat:@" %@", f.symbol ?: @""];
    }
    if ([all containsString:@"rangeorkindex"] || [all containsString:@"out of bounds"] ||
        [all containsString:@"nsrangeexception"]) {
        add(SPCrashSeverityWarn, @"数组 / 字符串越界",
            @"NSRangeException 常见于下标越界。",
            @"用 objectAtIndex 前判 count；NSMutableArray 遍历时不要边遍历边删。");
    }
    if ([all containsString:@"unrecognized selector"]) {
        add(SPCrashSeverityWarn, @"向对象发送了不存在的方法",
            @"NSInvalidArgumentException: unrecognized selector。",
            @"检查调用方的类型是否对（id 可能是别的类）；delegate 方法先 respondsToSelector。");
    }
    if ([all containsString:@"kvo"] || [all containsString:@"observed"]) {
        add(SPCrashSeverityWarn, @"KVO 相关崩溃",
            @"常见于 removeObserver 次数与 addObserver 不匹配。",
            @"用带 context 的 addObserver，并在 dealloc / 合适时机成对移除。");
    }

    // 7. tweak 相关：崩溃栈里有 CydiaSubstrate / 我们注入的库
    for (SPCrashFrame *f in r.frames) {
        NSString *img = f.image.lowercaseString;
        if ([img containsString:@"substrate"] || [img containsString:@"ellekit"] ||
            ([img hasSuffix:@".dylib"] && ![img hasPrefix:@"lib"])) {
            add(SPCrashSeverityWarn, @"崩溃栈里出现了注入的插件",
                [NSString stringWithFormat:@"%@ 出现在调用栈里（第 %lu 帧）。",
                 f.image, (unsigned long)[r.frames indexOfObject:f]],
                @"先在注入器里关掉这个插件试一次；确认是不是 hook 了系统类的私有方法。");
            break;
        }
    }

    // 8. 主线程上做 I/O（启发式）
    if ([r.triggeredThread containsString:@"main"] || !r.triggeredThread.length) {
        BOOL io = NO;
        for (SPCrashFrame *f in r.frames) {
            NSString *s = f.symbol.lowercaseString;
            if ([s containsString:@"filemanager"] || [s containsString:@"nsdata"] ||
                [s containsString:@"writetofile"] || [s containsString:@"readtoend"]) { io = YES; break; }
        }
        if (io) {
            add(SPCrashSeverityInfo, @"主线程上有文件 I/O",
                @"崩溃时主线程栈里有文件读写，容易触发看门狗。",
                @"移到后台队列，用 completion 回主线程更新 UI。");
        }
    }

    // 9. 我们的 App 自己
    for (SPCrashFrame *f in r.frames) {
        if ([f.image.lowercaseString containsString:@"spark"]) {
            add(SPCrashSeverityError, @"崩溃发生在 Spark 自身",
                [NSString stringWithFormat:@"第 %lu 帧在 %@ 里：%@",
                 (unsigned long)[r.frames indexOfObject:f], f.image, f.symbol ?: @"(无符号)"],
                @"带上这份 .ips 提 issue，我会按这个栈定位。");
            break;
        }
    }

    if (!out.count) {
        add(SPCrashSeverityInfo, @"未匹配到常见崩溃模式",
            @"可能是不常见的内核/驱动层问题，或缺少符号信息。",
            @"把同目录下的其他 .ips 一起看一下，找重复出现的帧。");
    }
    return out;
}

+ (NSString *)summaryForReport:(SPCrashReport *)r {
    NSMutableString *buf = [NSMutableString string];
    [buf appendFormat:@"%@", r.appName.length ? r.appName : @"应用"];
    if (r.exceptionType.length) [buf appendFormat:@" 崩溃：%@", r.exceptionType];
    if (r.signal.length) [buf appendFormat:@"（%@）", r.signal];
    SPCrashFinding *first = r.findings.firstObject;
    if (first && first.severity >= SPCrashSeverityWarn) {
        [buf appendFormat:@"\n结论：%@", first.title];
    }
    return buf;
}

#pragma mark - 扫描目录

+ (NSArray<SPCrashReport *> *)scanCommonDirectories {
    NSMutableArray *dirs = [NSMutableArray array];
    // TrollStore / 越狱设备上常见的崩溃日志位置
    [dirs addObjectsFromArray:@[
        @"/var/mobile/Library/Logs/CrashReporter",
        @"/private/var/mobile/Library/Logs/CrashReporter",
        @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
        @"/var/root/Library/Logs/CrashReporter",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark/crashes"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/CrashReporter"],
    ]];

    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *d in dirs) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:d error:NULL] ?: @[]) {
            NSString *low = name.lowercaseString;
            if ([low hasSuffix:@".ips"] || [low hasSuffix:@".crash"]) {
                [paths addObject:[d stringByAppendingPathComponent:name]];
            }
        }
    }
    // 按修改时间倒序
    [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *da = [fm attributesOfItemAtPath:a error:NULL][NSFileModificationDate] ?: [NSDate date];
        NSDate *db = [fm attributesOfItemAtPath:b error:NULL][NSFileModificationDate] ?: [NSDate date];
        return [db compare:da];
    }];

    NSMutableArray *reports = [NSMutableArray array];
    for (NSString *p in paths) {
        if (reports.count >= 60) break;   // 上限，避免一次解析太多
        SPCrashReport *r = [self analyzePath:p error:NULL];
        if (r) [reports addObject:r];
    }
    return reports;
}

#pragma mark - 导出

+ (NSString *)markdownForReport:(SPCrashReport *)r {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"# 崩溃分析报告\n\n"];
    [s appendFormat:@"- **应用**：%@（%@）\n", r.appName ?: @"?", r.bundleId ?: @"?"];
    [s appendFormat:@"- **版本**：%@\n", r.version ?: @"?"];
    [s appendFormat:@"- **系统**：%@  %@\n", r.osVersion ?: @"?", r.device ?: @""];
    if (r.crashTime) [s appendFormat:@"- **时间**：%@\n", r.crashTime];
    if (r.exceptionType.length) [s appendFormat:@"- **异常**：%@\n", r.exceptionType];
    if (r.signal.length) [s appendFormat:@"- **信号**：%@\n", r.signal];
    if (r.termination.length) [s appendFormat:@"- **终止原因**：%@\n", r.termination];
    if (r.triggeredThread.length) [s appendFormat:@"- **触发线程**：%@\n", r.triggeredThread];
    [s appendString:@"\n## 结论\n\n"];
    for (SPCrashFinding *f in r.findings) {
        NSString *mark = f.severity == SPCrashSeverityError ? @"❌"
                      : (f.severity == SPCrashSeverityWarn ? @"⚠️" : @"ℹ️");
        [s appendFormat:@"### %@ %@\n\n%@\n\n", mark, f.title, f.detail];
        if (f.suggestion.length) [s appendFormat:@"**建议**：%@\n\n", f.suggestion];
    }
    [s appendString:@"## 调用栈\n\n```\n"];
    for (SPCrashFrame *f in r.frames) {
        if (f.symbol.length) [s appendFormat:@"%@  %@\n", f.image, f.symbol];
        else [s appendFormat:@"%@  + 0x%llx\n", f.image, f.offset];
    }
    [s appendString:@"```\n\n"];
    [s appendFormat:@"<sub>来源：%@</sub>\n", r.path.lastPathComponent];
    return s;
}

@end
