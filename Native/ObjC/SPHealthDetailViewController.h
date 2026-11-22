//
//  SPHealthDetailViewController.h
//

#import <UIKit/UIKit.h>
#import "SPHealthCheck.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPHealthDetailViewController : UIViewController
- (instancetype)initWithItem:(SPHealthItem *)item;
@end

NS_ASSUME_NONNULL_END