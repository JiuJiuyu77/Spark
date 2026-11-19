//
//  spark-logos.m —— 命令行版 Logos 预处理器
//
//  用途：构建脚本在 make 之前调用，把 .x 展开成 .m。
//  为什么不在脚本里用 python：设备上不一定有可用的 python3
//  （Rein 带了但没暴露到 PATH），而 perl 又缺 libperl.dylib。
//  这个工具是原生二进制，零解释器依赖。
//
//  用法：spark-logos <input.x> <output.m>
//  退出码：0 成功；12 解析失败；其他为读写错误
//

#import <Foundation/Foundation.h>
#import "SPLogosPreprocessor.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "用法：spark-logos <input.x> <output.m>\n");
            return 2;
        }
        NSString *inp = @(argv[1]);
        NSString *outp = @(argv[2]);

        NSError *err = nil;
        NSString *src = [NSString stringWithContentsOfFile:inp
                                                  encoding:NSUTF8StringEncoding
                                                     error:&err];
        if (!src) {
            fprintf(stderr, "读取失败：%s\n", err.localizedDescription.UTF8String ?: "");
            return 3;
        }

        NSString *res = [SPLogosPreprocessor preprocess:src error:&err];
        if (!res) {
            fprintf(stderr, "预处理失败：%s\n", err.localizedDescription.UTF8String ?: "未知");
            return 12;
        }
        if (![res writeToFile:outp atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
            fprintf(stderr, "写入失败：%s\n", err.localizedDescription.UTF8String ?: "");
            return 4;
        }
        return 0;
    }
}
