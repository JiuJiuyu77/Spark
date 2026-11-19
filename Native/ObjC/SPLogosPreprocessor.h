//
//  SPLogosPreprocessor.h
//  Spark —— 内置 Logos 预处理器
//
//  为什么需要它
//  -----------
//  Theos 用 logos.pl 把 .x 文件里的 %hook 语法展开成 ObjC 代码。
//  logos.pl 是 Perl 脚本，而设备上所有 Theos 运行时（Rein / DSH / Codex）
//  的 perl 都依赖 libperl.dylib —— 这个库谁都没带。
//  结果：perl 跑不起来 → logos.pl 跑不起来 → 所有 .x 工程编不了。
//
//  这个模块用纯 C 实现同一套展开，不依赖 perl。
//  生成格式对齐 Logos::Generator::MobileSubstrate
//  （默认生成器，与 Theos 的 makefiles 一致）。
//
//  支持的指令
//  ---------
//    %hook / %end          类 hook
//    %group / %end         分组
//    %new                  新增方法
//    %orig                 调用原实现（支持传参）
//    %init / %ctor / %dtor 初始化器与构造/析构
//    %c(...)               类引用
//    %config(...)          配置
//    %hookf / %property    hook 函数 / 属性
//    %subclass            子类
//    %log                  参数日志
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPLogosPreprocessor : NSObject

/// 把 .x 源码展开为 ObjC 源码。
/// @param source .x 文件内容
/// @param error 失败原因（含行号）
/// @return 展开后的 ObjC 源码；失败返回 nil
+ (nullable NSString *)preprocess:(NSString *)source error:(NSError *_Nullable *_Nullable)error;

/// 直接处理文件：读 .x 写 .mi（或任意后缀）。返回是否成功。
+ (BOOL)preprocessFile:(NSString *)inputPath
                toPath:(NSString *)outputPath
                 error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
