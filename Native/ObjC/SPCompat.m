//
//  SPCompat.m
//

#import "SPCompat.h"

NSString *const SPErrorDomain = @"Spark.Error";

@implementation SPVersion

+ (instancetype)shared {
    static SPVersion *v; static dispatch_once_t once;
    dispatch_once(&once, ^{ v = [SPVersion new]; });
    return v;
}

- (NSString *)semver {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.0.0";
}

- (NSString *)gitDescribe {
    NSString *g = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SPGitDescribe"];
    return g.length ? g : @"dev";
}

- (NSString *)builtAt {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SPBuildDate"] ?: @"";
}

@end

@implementation SPUtil

+ (NSString *)formatDuration:(NSTimeInterval)seconds {
    NSInteger s = (NSInteger)MAX(0, seconds);
    if (s < 3600) return [NSString stringWithFormat:@"%02ld:%02ld", (long)(s / 60), (long)(s % 60)];
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(s / 3600), (long)((s % 3600) / 60), (long)(s % 60)];
}

+ (NSString *)formatBytes:(unsigned long long)bytes {
    static NSArray *units;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ units = @[@"B", @"KB", @"MB", @"GB", @"TB"]; });
    double v = (double)bytes; NSUInteger i = 0;
    while (v >= 1024.0 && i + 1 < units.count) { v /= 1024.0; i++; }
    return i == 0 ? [NSString stringWithFormat:@"%llu B", bytes]
                  : [NSString stringWithFormat:@"%.1f %@", v, units[i]];
}

+ (NSString *)shellQuote:(NSString *)s {
    if (s.length == 0) return @"''";
    // 不含特殊字符就直接返回，可读性更好
    NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:
                            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%_+=:,./-"];
    if ([s rangeOfCharacterFromSet:safe.invertedSet].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString stringWithString:@"'"];
    [out appendString:[s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
    [out appendString:@"'"];
    return out;
}

+ (NSArray<NSString *> *)envPairsFromDictionary:(NSDictionary<NSString *, NSString *> *)dict {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *k in keys) {
        NSString *v = dict[k];
        if (![v isKindOfClass:[NSString class]]) continue;
        // env 值里不能有换行，统统压成空格
        v = [v stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        [out addObject:[NSString stringWithFormat:@"%@=%@", k, v]];
    }
    return out;
}

+ (NSString *)stringFromPlistAtPath:(NSString *)path key:(NSString *)key default:(NSString *)def {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    id v = d[key];
    return [v isKindOfClass:[NSString class]] ? v : def;
}

+ (NSString *)timestampSlug {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyyMMdd-HHmmss";
    return [f stringFromDate:[NSDate date]];
}

+ (NSError *)copyDirectory:(NSString *)src to:(NSString *)dst {
    NSFileManager *fm = NSFileManager.defaultManager;
    [self removeItemIfExists:dst];
    NSError *err = nil;
    if (![fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES attributes:nil error:&err]) return err;
    if (![fm copyItemAtPath:src toPath:dst error:&err]) return err;
    return nil;
}

+ (void)removeItemIfExists:(NSString *)path {
    if (path.length) [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
}

+ (BOOL)ensureDirectory:(NSString *)path error:(NSError **)error {
    return [NSFileManager.defaultManager createDirectoryAtPath:path
                                   withIntermediateDirectories:YES attributes:nil error:error];
}

+ (NSString *)findExecutable:(NSArray<NSString *> *)names searchDirs:(NSArray<NSString *> *)dirs {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"/"]) { [candidates addObject:name]; continue; }
        for (NSString *d in dirs ?: @[]) [candidates addObject:[d stringByAppendingPathComponent:name]];
    }
    for (NSString *p in candidates) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir && [fm isExecutableFileAtPath:p]) return p;
    }
    // PATH 兜底
    NSString *PATH = [NSProcessInfo processInfo].environment[@"PATH"];
    for (NSString *d in [PATH componentsSeparatedByString:@":"]) {
        if (d.length == 0) continue;
        for (NSString *name in names) {
            if ([name hasPrefix:@"/"]) continue;
            NSString *p = [d stringByAppendingPathComponent:name];
            if ([fm isExecutableFileAtPath:p]) return p;
        }
    }
    return nil;
}

@end
