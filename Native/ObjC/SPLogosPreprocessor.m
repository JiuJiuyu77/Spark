//
//  SPLogosPreprocessor.m
//
//  纯 C/ObjC 实现的 Logos 预处理器。
//  输出格式对齐 Logos::Generator::MobileSubstrate（Theos 默认生成器）。
//

#import "SPLogosPreprocessor.h"
#import "SPCompat.h"

#pragma mark - 数据结构

/// 一个被 hook 的方法
@interface SPLLMethod : NSObject
@property (nonatomic, copy) NSString *name;          // 方法名（不含类型）
@property (nonatomic, copy) NSString *returnType;    // 返回类型
@property (nonatomic, copy) NSString *signature;     // 完整签名 (int, id)
@property (nonatomic, copy) NSString *argTypes;      // "int, id"
@property (nonatomic, copy) NSString *argNames;      // "a, b"
@property (nonatomic, assign) BOOL isClassMethod;    // + 方法
@property (nonatomic, assign) BOOL isNew;            // %new
@property (nonatomic, assign) BOOL isVariadic;
@property (nonatomic, copy) NSMutableString *body;
@end

@implementation SPLLMethod
- (instancetype)init {
    if ((self = [super init])) { _body = [NSMutableString string]; }
    return self;
}
@end

/// 一个 %hook 块
@interface SPLLClass : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<SPLLMethod *> *methods;
@property (nonatomic, copy) NSMutableString *prologue;   // 块内直接的 C 代码
@end

@implementation SPLLClass
- (instancetype)init {
    if ((self = [super init])) {
        _methods = [NSMutableArray array];
        _prologue = [NSMutableString string];
    }
    return self;
}
@end

/// 一个 %group
@interface SPLLGroup : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<SPLLClass *> *classes;
@property (nonatomic, strong) NSMutableArray<NSString *> *ctorLines;  // %init 里的代码
@end

@implementation SPLLGroup
- (instancetype)init {
    if ((self = [super init])) {
        _classes = [NSMutableArray array];
        _ctorLines = [NSMutableArray array];
    }
    return self;
}
@end

#pragma mark - 工具

/// 生成一个稳定的短哈希（替代 md5_hex，只用于唯一化符号名）
static NSString *SPLLShortHash(NSString *s) {
    uint64_t h = 1469598103934665603ULL;   // FNV-1a
    const char *p = s.UTF8String;
    for (size_t i = 0; p && p[i]; i++) {
        h ^= (unsigned char)p[i];
        h *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%08x", (unsigned int)(h >> 16)];
}

/// 从 "(int, id)x" 这样的签名里拆出返回类型与参数
static void SPLLParseSignature(NSString *sig, SPLLMethod *m) {
    NSString *s = [sig stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

    // 括号内的参数列表
    NSRange lp = [s rangeOfString:@"("];
    NSRange rp = [s rangeOfString:@")"];
    if (lp.location != NSNotFound && rp.location != NSNotFound && rp.location > lp.location) {
        NSString *inside = [s substringWithRange:NSMakeRange(lp.location + 1, rp.location - lp.location - 1)];
        NSMutableArray *types = [NSMutableArray array];
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *raw in [inside componentsSeparatedByString:@","]) {
            NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (!t.length) continue;
            // 参数可能带名字：`int x` → 类型是 int，名字是 x
            NSArray *parts = [t componentsSeparatedByCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray *words = [NSMutableArray array];
            for (NSString *w in parts) if (w.length) [words addObject:w];
            if (words.count >= 2) {
                // 最后一个是名字，其余是类型
                NSString *nm = words.lastObject;
                // 处理 `int *p` 这种：名字前可能有 *
                NSString *typ = [[words subarrayWithRange:NSMakeRange(0, words.count - 1)]
                                 componentsJoinedByString:@" "];
                if ([typ hasSuffix:@"*"] || [nm hasPrefix:@"*"]) { typ = [typ stringByAppendingString:@"*"]; }
                [types addObject:typ];
                [names addObject:[nm stringByReplacingOccurrencesOfString:@"*" withString:@""]];
            } else {
                [types addObject:t];
                [names addObject:[NSString stringWithFormat:@"arg%lu", (unsigned long)types.count]];
            }
        }
        m.argTypes = [types componentsJoinedByString:@", "];
        m.argNames = [names componentsJoinedByString:@", "];
        m.signature = [NSString stringWithFormat:@"(%@)", m.argTypes.length ? m.argTypes : @""];

        // 括号前的部分是返回类型
        NSString *before = [[s substringToIndex:lp.location]
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        // 括号后可能有名字
        NSString *after = [[s substringFromIndex:rp.location + 1]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

        if (!before.length) {
            // `-(id)foo` 这种：before 为空说明是 `- (id)foo` 在 methodSig 里已剥离
            m.returnType = @"id";
        } else {
            m.returnType = before;
        }
        m.name = after.length ? after : @"";
    } else {
        m.returnType = s.length ? s : @"id";
    }

    // 变参
    if ([m.argTypes rangeOfString:@"..."].location != NSNotFound) m.isVariadic = YES;
}

#pragma mark - 主实现

@implementation SPLogosPreprocessor

+ (nullable NSString *)preprocess:(NSString *)source error:(NSError **)error {
    if (!source.length) return source ?: @"";

    NSMutableArray<SPLLGroup *> *groups = [NSMutableArray array];
    SPLLGroup *mainGroup = [SPLLGroup new];
    mainGroup.name = @"_ungrouped";
    [groups addObject:mainGroup];

    SPLLGroup *curGroup = mainGroup;
    SPLLClass *curClass = nil;
    SPLLMethod *curMethod = nil;
    int hookDepth = 0;

    NSArray *lines = [source componentsSeparatedByString:@"\n"];
    NSMutableString *out = [NSMutableString string];

    for (NSUInteger ln = 0; ln < lines.count; ln++) {
        NSString *line = lines[ln];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

        // ── %hook ClassName ──
        if ([trimmed hasPrefix:@"%hook"] && ![trimmed hasPrefix:@"%hookf"]) {
            NSString *cls = [[trimmed substringFromIndex:5]
                             stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            // 去掉行尾注释
            if ([cls rangeOfString:@"//"].location != NSNotFound) {
                cls = [[cls componentsSeparatedByString:@"//"].firstObject
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            }
            SPLLClass *c = [SPLLClass new];
            c.name = cls;
            [curGroup.classes addObject:c];
            curClass = c;
            hookDepth = 1;
            continue;
        }

        // ── %group Name ──
        if ([trimmed hasPrefix:@"%group"]) {
            NSString *g = [[trimmed substringFromIndex:6]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            SPLLGroup *grp = [SPLLGroup new];
            grp.name = g;
            [groups addObject:grp];
            curGroup = grp;
            continue;
        }

        // ── %end ──
        if ([trimmed hasPrefix:@"%end"]) {
            if (hookDepth == 1) { curClass = nil; hookDepth = 0; }
            else if (!curClass) { curGroup = mainGroup; }
            continue;
        }

        // ── 在 %hook 块内 ──
        if (curClass) {
            // 方法定义：- (ret)name  或  + (ret)name
            if ([trimmed hasPrefix:@"-"] || [trimmed hasPrefix:@"+"]) {
                BOOL isClassMethod = [trimmed hasPrefix:@"+"];
                NSString *rest = [[trimmed substringFromIndex:1]
                                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

                SPLLMethod *m = [SPLLMethod new];
                m.isClassMethod = isClassMethod;
                m.isNew = NO;

                // 方法名可能带 %new 前缀
                if ([rest hasPrefix:@"%new"]) {
                    m.isNew = YES;
                    rest = [[rest substringFromIndex:4]
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                }

                // 解析 (ret)name 形式
                if ([rest hasPrefix:@"("]) {
                    NSRange rp = [rest rangeOfString:@")"];
                    if (rp.location != NSNotFound) {
                        NSString *inner = [rest substringWithRange:NSMakeRange(1, rp.location - 1)];
                        NSString *afterName = [[rest substringFromIndex:rp.location + 1]
                                               stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                        // 方法名可能自己带参数列表（methodSig 里）
                        SPLLParseSignature([NSString stringWithFormat:@"(%@)%@", inner, afterName], m);
                        if (!m.name.length) m.name = afterName;
                    }
                } else {
                    m.name = rest;
                    m.returnType = @"id";
                }

                // 去掉方法名尾部的 { 
                if ([m.name hasSuffix:@"{"]) m.name = [[m.name substringToIndex:m.name.length - 1]
                                                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

                [curClass.methods addObject:m];
                curMethod = m;
                // 方法体开始（该行可能有 {）
                if ([trimmed rangeOfString:@"{"].location != NSNotFound) {
                    NSString *after = [trimmed componentsSeparatedByString:@"{"].lastObject;
                    if (after.length) [curMethod.body appendFormat:@"%@\n", after];
                }
                continue;
            }

            // 方法体内：%orig / %new / 普通代码
            if (curMethod) {
                // %orig → 调用原实现
                if ([trimmed rangeOfString:@"%orig"].location != NSNotFound) {
                    NSString *replaced = [line stringByReplacingOccurrencesOfString:@"%orig"
                                                                        withString:curMethod.isNew ? @"" : @"_logos_orig"];
                    // 如果 %orig 后面没有括号，补上参数
                    if (!curMethod.isNew && curMethod.argNames.length &&
                        [replaced rangeOfString:@"_logos_orig"].location != NSNotFound) {
                        NSString *origCall = [NSString stringWithFormat:@"_logos_orig(self, _cmd%@%@)",
                                              curMethod.argNames.length ? @", " : @"", curMethod.argNames];
                        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"_logos_orig(?!\\s*\\()"
                                                                                           options:0 error:nil];
                        replaced = [re stringByReplacingMatchesInString:replaced options:0
                                                                  range:NSMakeRange(0, replaced.length)
                                                           withTemplate:origCall];
                    }
                    [curMethod.body appendFormat:@"%@\n", replaced];
                    continue;
                }
                // 方法体结束
                if ([trimmed hasPrefix:@"}"]) {
                    curMethod = nil;
                    continue;
                }
                [curMethod.body appendFormat:@"%@\n", line];
                continue;
            }

            // 块内非方法代码
            if ([trimmed hasPrefix:@"%init"] || [trimmed hasPrefix:@"%ctor"]) {
                NSString *code = [[trimmed substringFromIndex:5]
                                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                code = [code stringByTrimmingCharactersInSet:
                        [NSCharacterSet characterSetWithCharactersInString:@"(){}"]];
                if (code.length) [curClass.prologue appendFormat:@"static void _logos_group_init_%@(void) { %@ }\n",
                                  SPLLShortHash(curClass.name), code];
                continue;
            }
            [curClass.prologue appendFormat:@"%@\n", line];
            continue;
        }

        // ── 全局 %ctor ──
        if ([trimmed hasPrefix:@"%ctor"]) {
            NSString *code = [[trimmed substringFromIndex:4]
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            code = [code stringByTrimmingCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"(){}"]];
            if (code.length) [curGroup.ctorLines addObject:code];
            continue;
        }
        if ([trimmed hasPrefix:@"%dtor"]) {
            NSString *code = [[trimmed substringFromIndex:4]
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            code = [code stringByTrimmingCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"(){}"]];
            if (code.length) [curGroup.ctorLines addObject:code];
            continue;
        }
        if ([trimmed hasPrefix:@"%init"]) {
            NSString *code = [[trimmed substringFromIndex:5]
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            code = [code stringByTrimmingCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"(){}"]];
            if (code.length) [curGroup.ctorLines addObject:code];
            continue;
        }
        if ([trimmed hasPrefix:@"%config"]) {
            continue;   // 配置指令，不影响生成
        }

        // ── %c(...) → 展开为 objc_getClass("...") ──
        NSString *expanded = line;
        if ([expanded rangeOfString:@"%c("].location != NSNotFound) {
            NSRegularExpression *re =
                [NSRegularExpression regularExpressionWithPattern:@"%c\\(\\s*([^)]+?)\\s*\\)" options:0 error:nil];
            expanded = [re stringByReplacingMatchesInString:expanded options:0
                                                      range:NSMakeRange(0, expanded.length)
                                               withTemplate:@"objc_getClass(\"$1\")"];
        }
        [out appendFormat:@"%@\n", expanded];
    }

    // ── 生成代码 ──
    NSMutableString *gen = [NSMutableString string];

    [gen appendString:@"// 由 Spark 内置 Logos 预处理器生成（不依赖 perl）\n"];
    [gen appendString:@"#include <objc/runtime.h>\n"];
    [gen appendString:@"#include <objc/message.h>\n"];
    [gen appendString:@"\n"];

    for (SPLLGroup *g in groups) {
        for (SPLLClass *c in g.classes) {
            NSString *cls = c.name;
            NSString *safe = [cls stringByReplacingOccurrencesOfString:@"." withString:@"_"];

        }
    }

    // 简化：直接输出替换后的源码（把 %hook 块转成 C 函数 + 注册）
    // 为了可读性与稳健，这里采用「函数 + 构造器注册」的方式，
    // 与 Logos 的 MobileSubstrate 生成器语义一致。
    for (SPLLGroup *g in groups) {
        for (SPLLClass *c in g.classes) {
            NSString *cls = c.name;
            NSString *safe = [cls stringByReplacingOccurrencesOfString:@"." withString:@"_"];

            if (c.prologue.length) [gen appendFormat:@"%@\n", c.prologue];

            for (SPLLMethod *m in c.methods) {
                NSString *orig = [NSString stringWithFormat:@"_logos_orig$%@$%@", safe, m.name];
                NSString *func = [NSString stringWithFormat:@"_logos_method$%@$%@", safe, m.name];

                // 原函数指针声明
                if (!m.isNew) {
                    [gen appendFormat:@"static %@ (*%@)(%@, SEL%@%@);\n",
                     m.returnType.length ? m.returnType : @"id", orig, cls,
                     m.argTypes.length ? @", " : @"",
                     m.argTypes.length ? m.argTypes : @""];
                }

                // 函数定义
                [gen appendFormat:@"static %@ %@(%@ self, SEL _cmd%@%@) {\n",
                 m.returnType.length ? m.returnType : @"id", func, cls,
                 m.argTypes.length ? @", " : @"",
                 m.argNames.length ? m.argNames : @""];
                [gen appendString:m.body];
                [gen appendString:@"}\n\n"];
            }

            // 注册（%ctor 里做）
            [g.ctorLines addObject:[NSString stringWithFormat:@"_logos_register_%@()", safe]];
            [gen appendFormat:@"static void _logos_register_%@(void) {\n", safe];
            [gen appendFormat:@"    Class _cls = objc_getClass(\"%@\");\n", cls];
            [gen appendString:@"    if (!_cls) return;\n"];
            for (SPLLMethod *m in c.methods) {
                NSString *orig = [NSString stringWithFormat:@"_logos_orig$%@$%@", safe, m.name];
                NSString *func = [NSString stringWithFormat:@"_logos_method$%@$%@", safe, m.name];
                NSString *sel = m.name;
                // SEL 可能带参数，转成 selector 名：foo:bar:
                NSUInteger nargs = m.argNames.length ? [[m.argNames componentsSeparatedByString:@","] count] : 0;
                if (nargs > 0) {
                    NSArray *parts = [sel componentsSeparatedByString:@":"];
                    NSMutableString *s = [NSMutableString string];
                    for (NSUInteger i = 0; i < nargs; i++) {
                        if (i < parts.count) [s appendString:parts[i]];
                        [s appendString:@":"];
                    }
                    sel = s;
                }
                if (!m.isNew) {
                    [gen appendFormat:@"    { Method _m = class_getInstanceMethod(_cls, sel_registerName(\"%@\")); "
                                      "if (_m) %@ = (void *)method_getImplementation(_m); }\n", sel, orig];
                    [gen appendFormat:@"    { Method _m = class_getInstanceMethod(_cls, sel_registerName(\"%@\")); "
                                      "if (_m) method_setImplementation(_m, (IMP)%@); }\n", sel, func];
                } else {
                    [gen appendFormat:@"    class_addMethod(_cls, sel_registerName(\"%@\"), (IMP)%@, \"%@\");\n",
                     sel, func, [NSString stringWithFormat:@"%@%@", m.returnType, m.signature]];
                }
            }
            [gen appendString:@"}\n\n"];
        }

        // 该组的 ctor
        if (g.ctorLines.count) {
            [gen appendFormat:@"__attribute__((constructor)) static void _logos_ctor_%@(void) {\n", g.name];
            for (NSString *l in g.ctorLines) {
                [gen appendFormat:@"    %@;\n", l];
            }
            [gen appendString:@"}\n\n"];
        }
    }

    [out appendString:@"\n"];
    [out appendString:gen];
    return out;
}

+ (BOOL)preprocessFile:(NSString *)inputPath toPath:(NSString *)outputPath error:(NSError **)error {
    NSString *src = [NSString stringWithContentsOfFile:inputPath encoding:NSUTF8StringEncoding error:error];
    if (!src) return NO;
    NSString *res = [self preprocess:src error:error];
    if (!res) return NO;
    return [res writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end
