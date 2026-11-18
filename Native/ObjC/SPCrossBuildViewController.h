//
//  SPCrossBuildViewController.h
//  Spark —— 快速编译（clang 交叉编译，不依赖 Theos）
//
//  用系统 clang + ld64.lld 直接把 .m 编成已签名的 arm64 dylib，
//  不需要 root、不需要展开 125MB 的 Theos 工具链。
//
//  适用：手头只有一两个 .m 想快速出 dylib 验证效果；
//  不适用：完整 tweak 工程（含 Logos .x / 多文件 / .deb 打包）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPCrossBuildViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

NS_ASSUME_NONNULL_END
