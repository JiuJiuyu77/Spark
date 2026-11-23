//
//  SPReverseViewController.h
//  Workbench —— 逆向工具台：Mach-O 信息、依赖、符号、字符串、注入 dylib、签名
//

#import <UIKit/UIKit.h>
#import "SPToolchain.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPReverseViewController : UIViewController

- (instancetype)initWithBinaryPath:(nullable NSString *)binaryPath profile:(nullable SPToolchainProfile *)profile;

/// 直接给一个可执行文件跑 radare2 分析，返回文本（同步，调用方自行放到后台）
+ (NSString *)analyzeBinary:(NSString *)path
                   profile:(SPToolchainProfile *)profile
                      mode:(NSString *)mode  // info / symbols / strings / imports / sections / entropy
                      limit:(NSInteger)limit;

@end

NS_ASSUME_NONNULL_END
