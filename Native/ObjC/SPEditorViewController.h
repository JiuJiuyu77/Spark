//
//  SPEditorViewController.h
//  Workbench —— 带行号与语法着色的只读编辑器（可临时编辑并保存）
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPEditorViewController : UIViewController

- (instancetype)initWithFilePath:(NSString *)path;

@property (nonatomic, copy, nullable) void (^onSave)(NSString *path, NSString *text);
@property (nonatomic, assign) BOOL readOnly;

@end

NS_ASSUME_NONNULL_END
