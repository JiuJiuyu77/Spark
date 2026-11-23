//
//  SPBackground.m
//

#import "SPBackground.h"
#import "SPCompat.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface SPBackground ()
@property (nonatomic, strong) AVAudioPlayer *silentPlayer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *reasons;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, strong, nullable) NSDate *lastSuspendedAt;
@end

@implementation SPBackground

+ (instancetype)shared {
    static SPBackground *b; static dispatch_once_t once;
    dispatch_once(&once, ^{
        b = [SPBackground new];
        b.reasons = [NSMutableDictionary dictionary];
        b.bgTask = UIBackgroundTaskInvalid;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        b.userEnabled = [d objectForKey:@"Workbench.keepAlive"] == nil ? YES : [d boolForKey:@"Workbench.keepAlive"];

        // 切前台/后台时维护兜底任务
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
            __strong typeof(b) self = b;
            if (self.activeTaskCount > 0) [self beginBackgroundTask];
        }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
            __strong typeof(b) self = b;
            [self endBackgroundTask];
        }];
        [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
            __strong typeof(b) self = b;
            self.lastSuspendedAt = [NSDate date];
        }];
    });
    return b;
}

- (BOOL)isActive { return self.silentPlayer.isPlaying; }
- (NSInteger)activeTaskCount { return (NSInteger)self.reasons.count; }

- (void)setUserEnabled:(BOOL)userEnabled {
    _userEnabled = userEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:userEnabled forKey:@"Workbench.keepAlive"];
    if (!userEnabled) {
        [self.reasons removeAllObjects];
        [self stopAudio];
    }
}

#pragma mark - 保活计数

- (void)beginKeepAlive:(NSString *)reason {
    if (!self.userEnabled) return;
    NSString *key = reason.length ? reason : @"task";
    NSInteger n = self.reasons[key].integerValue;
    self.reasons[key] = @(n + 1);
    SPLog(@"后台保活 +1 (%@) → 共 %ld", key, (long)self.activeTaskCount);
    [self startAudio];
}

- (void)endKeepAlive:(NSString *)reason {
    NSString *key = reason.length ? reason : @"task";
    NSInteger n = self.reasons[key].integerValue;
    if (n <= 1) [self.reasons removeObjectForKey:key];
    else self.reasons[key] = @(n - 1);
    SPLog(@"后台保活 -1 (%@) → 共 %ld", key, (long)self.activeTaskCount);
    if (self.activeTaskCount == 0) {
        [self stopAudio];
        [self endBackgroundTask];
    }
}

#pragma mark - 静音音频

/// 生成 1 秒静音 WAV（44 字节头 + 全 0 采样），避免仓库里塞音频文件
- (nullable NSData *)silentWAVData {
    const uint32_t sampleRate = 8000;
    const uint16_t channels = 1;
    const uint16_t bitsPerSample = 16;
    const uint32_t numSamples = sampleRate;           // 1 秒
    const uint32_t dataSize = numSamples * channels * (bitsPerSample / 8);

    NSMutableData *d = [NSMutableData data];
    // 小端写 32 位
    void (^put32)(uint32_t) = ^(uint32_t v) {
        uint8_t b[4] = { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF),
                         (uint8_t)((v >> 16) & 0xFF), (uint8_t)((v >> 24) & 0xFF) };
        [d appendBytes:b length:4];
    };
    // 小端写 16 位
    void (^put16)(uint16_t) = ^(uint16_t v) {
        uint8_t b[2] = { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF) };
        [d appendBytes:b length:2];
    };

    [d appendBytes:"RIFF" length:4];
    put32(36 + dataSize);
    [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4];
    put32(16);
    put16(1);                                   // PCM
    put16(channels);
    put32(sampleRate);
    put32(sampleRate * channels * (bitsPerSample / 8));   // byte rate
    put16((uint16_t)(channels * (bitsPerSample / 8)));    // block align
    put16(bitsPerSample);
    [d appendBytes:"data" length:4];
    put32(dataSize);
    [d appendData:[NSMutableData dataWithLength:dataSize]];   // 全静音
    return d;
}

- (void)startAudio {
    if (!self.userEnabled || self.silentPlayer.isPlaying) return;

    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    // 用 ambient：不打断用户的音乐，也不抢音频焦点
    [session setCategory:AVAudioSessionCategoryAmbient
                    mode:AVAudioSessionModeDefault
                 options:AVAudioSessionCategoryOptionMixWithOthers
                   error:&err];
    if (err) SPLog(@"后台保活：设置音频会话失败 %@", err.localizedDescription);
    [session setActive:YES error:&err];

    NSData *wav = [self silentWAVData];
    if (!wav) return;
    self.silentPlayer = [[AVAudioPlayer alloc] initWithData:wav error:&err];
    if (err) {
        SPLog(@"后台保活：创建播放器失败 %@", err.localizedDescription);
        return;
    }
    self.silentPlayer.numberOfLoops = -1;      // 无限循环
    self.silentPlayer.volume = 0.0;            // 完全静音
    BOOL ok = [self.silentPlayer play];
    SPLog(@"后台保活：%@", ok ? @"已启动" : @"启动失败");
}

- (void)stopAudio {
    if (self.silentPlayer) {
        [self.silentPlayer stop];
        self.silentPlayer = nil;
    }
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setActive:NO
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:&err];
    SPLog(@"后台保活：已停止");
}

#pragma mark - 兜底后台任务

- (void)beginBackgroundTask {
    if (self.bgTask != UIBackgroundTaskInvalid) return;
    __weak typeof(self) weakSelf = self;
    self.bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"Workbench.build"
        expirationHandler:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        SPLog(@"后台任务即将到期，保存状态");
        self.lastSuspendedAt = [NSDate date];
        [self endBackgroundTask];
    }];
}

- (void)endBackgroundTask {
    if (self.bgTask == UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
    self.bgTask = UIBackgroundTaskInvalid;
}

#pragma mark - 状态

- (NSString *)statusText {
    if (!self.userEnabled) return @"已关闭";
    if (self.activeTaskCount == 0) return @"待命（有长任务时才启用）";
    return [NSString stringWithFormat:@"保活中 · %ld 个任务", (long)self.activeTaskCount];
}

@end
