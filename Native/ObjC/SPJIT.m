//
//  SPJIT.m
//

#import "SPJIT.h"
#import "SPCompat.h"
#import "SPJITService.h"
#import <sys/mman.h>
#import <mach/vm_statistics.h>

@implementation SPJIT

+ (instancetype)shared {
    static SPJIT *j; static dispatch_once_t once;
    dispatch_once(&once, ^{
        j = [SPJIT new];
        j->_userEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"Workbench.jitEnabled"] == nil
            ? YES : [[NSUserDefaults standardUserDefaults] boolForKey:@"Workbench.jitEnabled"];
    });
    return j;
}

- (void)setUserEnabled:(BOOL)userEnabled {
    _userEnabled = userEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:userEnabled forKey:@"Workbench.jitEnabled"];
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
    // 1) 先试 JIT 子进程（最可靠：独立身份，能拿可执行内存）
    NSError *svcErr = nil;
    if ([[SPJITService shared] verifyExecutableMemoryWithError:&svcErr]) {
        _enabled = YES;
        _viaSubprocess = YES;
        _lastProbe = [NSDate date];
        SPLog(@"JIT 探测：可用（子进程 pid=%d）", (int)[[SPJITService shared] helperPid]);
        return;
    }

    // 2) 子进程不可用 → 退回主进程 mmap
    void *p = [self allocateExecutable:4096];
    _viaSubprocess = NO;
    if (p) {
        _enabled = YES;
        [self freeExecutable:p size:4096];
    } else {
        _enabled = NO;
    }
    _lastProbe = [NSDate date];
    SPLog(@"JIT 探测：%@（主进程；子进程原因：%@）",
          _enabled ? @"可用" : @"不可用", svcErr.localizedDescription ?: @"-");
}

/// 启动时把 helper 拉起来（不阻塞主线程）
- (void)startServiceIfNeeded {
    if (!self.userEnabled) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[SPJITService shared] start];
        [self probe];
    });
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
        return self.viaSubprocess
            ? @"可用 · JIT 子进程"
            : @"可用 · 主进程分配";
    }
    NSString *helper = [SPJITService shared].helperPath;
    if (!helper) return @"不可用 —— 缺少 JIT 子进程（bin/spark-jitd）";
    return [NSString stringWithFormat:@"不可用 —— 子进程 %@，主进程也无可执行内存权限",
            [SPJITService shared].statusText];
}

@end
