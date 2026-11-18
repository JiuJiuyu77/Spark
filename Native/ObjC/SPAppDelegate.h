//
//  SPAppDelegate.h
//  Spark

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 详情页可以隐藏悬浮底栏（编译控制台等需要全屏的操作页）
FOUNDATION_EXPORT void SPSetFloatBarHidden(BOOL hidden, BOOL animated);

@interface SPAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

NS_ASSUME_NONNULL_END
