//
//  main.m —— Share Extension 入口
//
//  .appex 是 XPC! 类型的 bundle，必须由 NSExtensionMain 作为入口，
//  不能像普通 App 那样用 UIApplicationMain。
//  （CMA 与手工 clang 链接时都需要它，否则报 undefined symbol _main）
//

#import <Foundation/Foundation.h>

// NSExtensionMain 由 Foundation 提供，系统会读 Info.plist 的
// NSExtensionPointIdentifier / NSExtensionPrincipalClass 来加载我们的类。
extern int NSExtensionMain(int argc, char *argv[]);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return NSExtensionMain(argc, argv);
    }
}
