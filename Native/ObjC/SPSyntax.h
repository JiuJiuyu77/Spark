//
//  SPSyntax.h
//  Spark —— 极轻量的语法着色器（Regex 驱动，够用且不卡）
//  支持：Logos/ObjC/C/C++/Swift/Makefile/JSON/Shell/Plist
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPSyntax : NSObject

/// 根据扩展名返回语言标识
+ (NSString *)languageForFile:(NSString *)path;

/// 给一段代码上色，返回 attributed string
+ (NSAttributedString *)highlight:(NSString *)code
                         language:(NSString *)language
                            color:(UIColor *)baseColor
                        darkTheme:(BOOL)darkTheme;

/// 生成简易行号视图用的行数
+ (NSInteger)lineCount:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
