//
//  SPJIT.m
//

#import "SPJIT.h"
#import "SPCompat.h"
#import <sys/mman.h>
#import <mach/vm_statistics.h>

@implementation SPJIT

+ (instancetype)shared {
    static SPJIT *j; static dispatch_once_t once;
    dispatch_once(&once, ^{
        j = [SPJIT new];
        j->_userEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"Spark.jitEnabled"] == nil
            ? YES : [[NSUserDefaults standardUserDefaults] boolForKey:@"Spark.jitEnabled"];
    });
    return j;
}

- (void)setUserEnabled:(BOOL)userEnabled {
    _userEnabled = userEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:userEnabled forKey:@"Spark.jitEnabled"];
}

- (BOOL)isPlatformApp {
    // 有 no-sandbox 权限的 App 一定不是普通 App Store 签名
    // 这里用「能否读取 /private/var/containers/Bundle/Application」间接判断
    NSFileManager *fm = NSFileManager.defaultManager;
    return [fm isReadableFileAtPath:@"/private/var/containers/Bundle/Application"]
        || [fm isReadableFileAtPath:@"/var/jb/Library"]
        || [fm isReadableFileAtPath:@"/Applications"];
}

- (void)probe {
    void *p = [self allocateExecutable:4096];
    if (p) {
        _enabled = YES;
        [self freeExecutable:p size:4096];
    } else {
        _enabled = NO;
    }
    _lastProbe = [NSDate date];
    SPLog(@"JIT 探测：%@（平台级=%@）", _enabled ? @"可用" : @"不可用", self.isPlatformApp ? @"是" : @"否");
}

- (void *)allocateExecutable:(size_t)size {
    if (!self.userEnabled) return NULL;

    // 1) 首选：RWX 直接映射（平台级 App 允许）
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                   MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (p != MAP_FAILED) return p;

    // 2) 退回：RW 映射后再 mprotect 成 RX（W^X 友好）
    p = mmap(NULL, size, PROT_READ | PROT_WRITE,
             MAP_ANON | MAP_PRIVATE, -1, 0);
    if (p == MAP_FAILED) return NULL;
    if (mprotect(p, size, PROT_READ | PROT_EXEC) != 0) {
        munmap(p, size);
        return NULL;
    }
    return p;
}

- (void)freeExecutable:(void *)ptr size:(size_t)size {
    if (ptr) munmap(ptr, size);
}

- (NSString *)statusText {
    if (!self.userEnabled) return @"已关闭（设置里可开启）";
    if (!self.lastProbe) return @"未探测";
    if (self.enabled) {
        return self.isPlatformApp
            ? @"可用 · 平台级内存权限"
            : @"可用 · 运行时分配可执行内存";
    }
    return @"不可用 —— 需要 TrollStore / 越狱，或用带 get-task-allow 的签名";
}

@end
