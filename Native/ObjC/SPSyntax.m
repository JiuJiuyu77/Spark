//
//  SPSyntax.m
//

#import "SPSyntax.h"
#import <UIKit/UIKit.h>

@implementation SPSyntax

+ (NSString *)languageForFile:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"x"] || [ext isEqualToString:@"xm"] || [ext isEqualToString:@"xi"]) return @"logos";
    if ([ext isEqualToString:@"m"] || [ext isEqualToString:@"h"] || [ext isEqualToString:@"mm"]) return @"objc";
    if ([ext isEqualToString:@"c"] || [ext isEqualToString:@"cc"] || [ext isEqualToString:@"cpp"] ||
        [ext isEqualToString:@"hpp"]) return @"c";
    if ([ext isEqualToString:@"swift"]) return @"swift";
    if ([path.lastPathComponent isEqualToString:@"Makefile"] || [ext isEqualToString:@"mk"]) return @"make";
    if ([ext isEqualToString:@"json"]) return @"json";
    if ([ext isEqualToString:@"sh"] || [ext isEqualToString:@"zsh"]) return @"shell";
    if ([ext isEqualToString:@"plist"] || [ext isEqualToString:@"xml"]) return @"xml";
    if ([ext isEqualToString:@"pl"]) return @"perl";
    return @"text";
}

+ (NSInteger)lineCount:(NSString *)code {
    if (!code.length) return 0;
    NSInteger n = 1;
    for (NSUInteger i = 0; i < code.length; i++) if ([code characterAtIndex:i] == '\n') n++;
    return n;
}

typedef struct { __unsafe_unretained NSString *pattern; NSUInteger group; int kind; } SPTokenRule;

// kind: 0 关键字 1 字符串 2 注释 3 数字 4 预处理 5 Logos 指令
+ (NSAttributedString *)highlight:(NSString *)code
                         language:(NSString *)language
                            color:(UIColor *)baseColor
                        darkTheme:(BOOL)darkTheme {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:code ?: @""];
    if (a.length == 0) return a;

    // 深浅色各一套：浅色模式下要压暗，否则白底上偏浅的紫/绿几乎看不见
    UIColor *(^dyn)(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) =
    ^UIColor *(CGFloat rD, CGFloat gD, CGFloat bD, CGFloat rL, CGFloat gL, CGFloat bL) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            BOOL dark = tc.userInterfaceStyle == UIUserInterfaceStyleDark;
            return [UIColor colorWithRed:(dark ? rD : rL) green:(dark ? gD : gL)
                                   blue:(dark ? bD : bL) alpha:1.0];
        }];
    };
    UIColor *kw   = dyn(0.80, 0.52, 0.98, 0.55, 0.15, 0.78);   // 关键字：紫
    UIColor *str  = dyn(0.55, 0.82, 0.52, 0.13, 0.52, 0.22);   // 字符串：绿
    UIColor *cmt  = dyn(0.45, 0.50, 0.56, 0.45, 0.50, 0.56);   // 注释：灰
    UIColor *num  = dyn(0.95, 0.70, 0.42, 0.72, 0.40, 0.05);   // 数字：橙
    UIColor *pre  = dyn(0.45, 0.72, 0.98, 0.10, 0.36, 0.72);   // 预处理：蓝
    UIColor *lg   = dyn(0.20, 0.84, 0.64, 0.05, 0.50, 0.40);   // Logos：青

    [a addAttribute:NSForegroundColorAttributeName value:baseColor range:NSMakeRange(0, a.length)];

    NSMutableArray<NSString *> *rules = [NSMutableArray array];
    // 通用：注释、字符串
    [rules addObject:@"//[^\\n]*$||2"];
    [rules addObject:@"/\\*[\\s\\S]*?\\*/||2"];
    [rules addObject:@"\"(?:[^\"\\\\\\n]|\\\\.)*\"||1"];
    [rules addObject:@"'(?:[^'\\\\\\n]|\\\\.)*'||1"];
    [rules addObject:@"\\b0x[0-9a-fA-F]+\\b|\\b\\d+(?:\\.\\d+)?[fFlLuU]*\\b||4"];
    [rules addObject:@"^\\s*#[A-Za-z_]+||5"];
    [rules addObject:@"@\\w+||5"];

    NSArray *kws = @[@"if",@"else",@"for",@"while",@"do",@"switch",@"case",@"break",@"continue",
                     @"return",@"void",@"int",@"char",@"float",@"double",@"long",@"short",@"unsigned",
                     @"signed",@"struct",@"enum",@"union",@"typedef",@"static",@"extern",@"const",
                     @"sizeof",@"goto",@"class",@"interface",@"implementation",@"protocol",@"property",
                     @"synthesize",@"dynamic",@"nonatomic",@"strong",@"weak",@"copy",@"readonly",
                     @"self",@"super",@"nil",@"YES",@"NO",@"id",@"instancetype",@"BOOL",@"let",@"var",
                     @"func",@"guard",@"in",@"where",@"init",@"deinit",@"true",@"false",@"null",
                     @"nullptr",@"override",@"public",@"private",@"protected",@"try",@"catch",
                     @"throw",@"throws",@"async",@"await",@"import",@"include",@"define",@"endif",
                     @"pragma",@"@interface",@"@implementation",@"@end",@"@selector",@"@property"];
    NSString *kwPattern = [NSString stringWithFormat:@"\\b(?:%@)\\b||0",
                           [[kws valueForKey:@"description"] componentsJoinedByString:@"|"]];
    [rules addObject:kwPattern];

    if ([language isEqualToString:@"logos"]) {
        [rules addObject:@"%\\w+||6"];
        [rules addObject:@"\\b(?:%hook|%end|%orig|%new|%c|%init|%group|%subclass|%ctor|%dtor)\\b||6"];
    }
    if ([language isEqualToString:@"make"]) {
        [rules addObject:@"^[A-Za-z_][A-Za-z0-9_]*\\s*(?=[:+?]?=)||0"];
        [rules addObject:@"\\$\\([^)]*\\)||5"];
    }
    if ([language isEqualToString:@"json"]) {
        [rules addObject:@"\"[^\"]*\"(?=\\s*:)||5"];
    }

    for (NSString *r in rules) {
        NSArray *parts = [r componentsSeparatedByString:@"||"];
        if (parts.count < 2) continue;
        NSString *pattern = parts[0];
        int kind = [parts[1] intValue];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                        options:NSRegularExpressionAnchorsMatchLines error:NULL];
        if (!re) continue;
        UIColor *c = baseColor;
        switch (kind) {
            case 0: c = kw; break;
            case 1: c = str; break;
            case 2: c = cmt; break;
            case 4: c = num; break;
            case 5: c = pre; break;
            case 6: c = lg; break;
        }
        [re enumerateMatchesInString:code options:0 range:NSMakeRange(0, code.length)
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
            if (m.range.location == NSNotFound || m.range.length == 0) return;
            [a addAttribute:NSForegroundColorAttributeName value:c range:m.range];
            if (kind == 2 || kind == 1) {
                [a addAttribute:NSFontAttributeName value:[UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular]
                          range:m.range];
            }
        }];
    }
    return a;
}

@end
