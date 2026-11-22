//
//  SPHealthDetailViewController.h
//

#import <UIKit/UIKit.h>
#import "SPHealthCheck.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPHealthDetailViewController : UIViewController
/// 要展示的检查项。实现里用 _item 访问，所以必须在头文件声明，
/// 否则 ARC 下不会自动合成实例变量，会报 use of undeclared identifier '_item'。
@property (nonatomic, strong) SPHealthItem *item;
- (instancetype)initWithItem:(SPHealthItem *)item;
@end

NS_ASSUME_NONNULL_END