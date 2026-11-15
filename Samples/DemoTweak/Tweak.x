// Spark 示例：最简单的 SpringBoard hook
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[DemoTweak] 已加载，Spark 构建成功");
}

%end
