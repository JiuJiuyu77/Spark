// Workbench 示例：最简单的 SpringBoard hook
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[DemoTweak] 已加载，Workbench 构建成功");
}

%end
