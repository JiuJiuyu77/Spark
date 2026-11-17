//
//  SPCrossBuildViewController.h
//  Spark —— 无 Theos 快速编译（ish 交叉编译路线）
//
//  用 ish 自带的 clang + ld64.lld 直接把 .m 编成已签名的 arm64 dylib，
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
