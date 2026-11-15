//
//  SPAutofix.m
//

#import "SPAutofix.h"
#import "SPCompat.h"

@implementation SPFixIt
@end

@implementation SPAutofix

#pragma mark - 解析

/// 编译错误的统一格式：path:line:col: error: message
+ (nullable NSArray<NSString *> *)fieldsOfDiagnosticLine:(NSString *)line {
    // 用正则抓 path:line:col: severity: message
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"^(.+?\\.(?:x|xm|m|mm|c|cc|cpp|h|hpp|swift)):(\\d+):(\\d+):\\s*(error|warning|fatal error):\\s*(.+)$"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!m || m.numberOfRanges < 6) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 1; i < 6; i++) {
        NSRange r = [m rangeAtIndex:i];
        [out addObject:r.location == NSNotFound ? @"" : [line substringWithRange:r]];
    }
    return out;
}

+ (NSArray<SPFixIt *> *)parseLog:(NSString *)logText projectRoot:(NSString *)root {
    if (!logText.length) return @[];
    NSMutableArray<SPFixIt *> *fixes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    NSArray<NSString *> *lines = [logText componentsSeparatedByString:@"\n"];
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSString *raw = lines[i];
        NSArray<NSString *> *f = [self fieldsOfDiagnosticLine:raw];
        if (!f) continue;

        NSString *file = f[0];
        NSInteger lineNo = f[1].integerValue;
        NSString *severity = f[3].lowercaseString;
        NSString *msg = f[4];
        if (![severity containsString:@"error"]) continue;   // 只处理 error

        // 绝对路径 / 相对路径统一成绝对
        NSString *fullPath = [file hasPrefix:@"/"] ? file : [root stringByAppendingPathComponent:file];
        NSString *key = [NSString stringWithFormat:@"%@:%ld", fullPath, (long)lineNo];
        if ([seen containsObject:key]) continue;

        NSString *lower = msg.lowercaseString;

        // 规则 1：expected ';' —— 缺分号
        if ([lower containsString:@"expected ';'"] || [lower containsString:@"expected a ';'"]) {
            SPFixIt *fix = [SPFixIt new];
            fix.ruleId = @"missing-semicolon";
            fix.ruleName = @"补分号";
            fix.filePath = fullPath;
            fix.line = lineNo;
            fix.reason = @"编译器提示这一行缺少分号";
            fix.safe = YES;
            [fixes addObject:fix];
            [seen addObject:key];
            continue;
        }

        // 规则 2：use of undeclared identifier 'UIKit' / 找不到头文件
        if ([lower containsString:@"'uikit/uikit.h' file not found"] ||
            [lower containsString:@"'foundation/foundation.h' file not found"]) {
            SPFixIt *fix = [SPFixIt new];
            fix.ruleId = @"missing-framework-header";
            fix.ruleName = @"引入系统头文件";
            fix.filePath = fullPath;
            fix.line = lineNo;
            fix.reason = @"看起来是 SDK / 框架没链接，通常是 Makefile 少了 _FRAMEWORKS";
            fix.safe = NO;   // 需要改 Makefile，不自动改
            [fixes addObject:fix];
            [seen addObject:key];
            continue;
        }

        // 规则 3：unused variable（warning 级，仅提示）
        if ([lower containsString:@"unused variable"]) continue;
    }

    // 给每条填 before/after 快照
    NSMutableArray<SPFixIt *> *out = [NSMutableArray array];
    for (SPFixIt *fix in fixes) {
        NSString *content = [NSString stringWithContentsOfFile:fix.filePath
                                                     encoding:NSUTF8StringEncoding error:NULL];
        if (!content.length) continue;
        NSArray<NSString *> *fileLines = [content componentsSeparatedByString:@"\n"];
        if (fix.line < 1 || fix.line > (NSInteger)fileLines.count) continue;

        NSString *before = fileLines[fix.line - 1];
        fix.beforeText = before;
        if ([fix.ruleId isEqualToString:@"missing-semicolon"]) {
            fix.afterText = [before stringByAppendingString:@";"];
        } else {
            fix.afterText = before;   // 不自动改的规则，快照保持原样
        }
        [out addObject:fix];
    }
    return out;
}

#pragma mark - 应用

+ (BOOL)applyFixes:(NSArray<SPFixIt *> *)fixes error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;

    // 按文件分组，避免同一文件反复读写
    NSMutableDictionary<NSString *, NSMutableArray<SPFixIt *> *> *byFile = [NSMutableDictionary dictionary];
    for (SPFixIt *f in fixes) {
        if (!f.safe) continue;
        if (!byFile[f.filePath]) byFile[f.filePath] = [NSMutableArray array];
        [byFile[f.filePath] addObject:f];
    }

    for (NSString *path in byFile) {
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
        if (!content.length) return NO;

        // 备份
        NSString *backup = [path stringByAppendingString:@".sparkbak"];
        [fm removeItemAtPath:backup error:NULL];
        if (![fm copyItemAtPath:path toPath:backup error:error]) return NO;

        NSMutableArray<NSString *> *lines = [[content componentsSeparatedByString:@"\n"] mutableCopy];
        // 从后往前改，避免行号错位
        NSArray *sorted = [byFile[path] sortedArrayUsingComparator:^NSComparisonResult(SPFixIt *a, SPFixIt *b) {
            return a.line > b.line ? NSOrderedAscending : NSOrderedDescending;
        }];
        for (SPFixIt *f in sorted) {
            if (f.line < 1 || f.line > (NSInteger)lines.count) continue;
            lines[f.line - 1] = f.afterText;
        }
        NSString *newContent = [lines componentsJoinedByString:@"\n"];
        if (![newContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) {
            // 写失败就把备份还原
            [fm removeItemAtPath:path error:NULL];
            [fm copyItemAtPath:backup toPath:path error:NULL];
            return NO;
        }
    }
    return YES;
}

#pragma mark - 撤销

+ (BOOL)canRevert:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingString:@".sparkbak"]];
}

+ (BOOL)revertFile:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *backup = [path stringByAppendingString:@".sparkbak"];
    if (![fm fileExistsAtPath:backup]) {
        if (error) *error = SPError(SPErrorCodeIO, @"没有找到备份文件");
        return NO;
    }
    [fm removeItemAtPath:path error:NULL];
    return [fm moveItemAtPath:backup toPath:path error:error];
}

@end
