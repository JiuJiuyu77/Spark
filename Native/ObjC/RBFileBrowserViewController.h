//
//  RBFileBrowserViewController.h
//  ReinBuild —— 项目文件树 / 任意目录浏览
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RBFilePickHandler)(NSString *path, BOOL isDirectory);

@interface RBFileBrowserViewController : UIViewController

/// 浏览某个目录；pickMode=YES 时点文件会回调 onPick 并关闭
- (instancetype)initWithRootPath:(NSString *)rootPath
                        pickMode:(BOOL)pickMode
                     fileFilters:(nullable NSArray<NSString *> *)extensions // 例如 @[@"deb"]
                      onPick:(nullable RBFilePickHandler)onPick;

@property (nonatomic, copy, nullable) void (^onOpenFile)(NSString *path);

@end

NS_ASSUME_NONNULL_END
