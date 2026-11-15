// 故意：%hook 没有对应 %end，且用了不存在的类型
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig
    NSLog(@"这里少了分号")
}
