//
//  SPConsoleViewController.m
//

#import "SPConsoleViewController.h"
#import "SPTheme.h"
#import "SPLogView.h"
#import "SPBuilder.h"
#import "SPSession.h"
#import "SPStore.h"
#import "SPCompat.h"
#import "SPEditorViewController.h"
#import "SPFileBrowserViewController.h"

@interface SPConsoleViewController () <UISearchBarDelegate>
@property (nonatomic, strong) SPProject *project;
@property (nonatomic, strong) SPToolchainProfile *profile;
@property (nonatomic, strong) SPLogView *logView;
@property (nonatomic, strong) SPSession *session;
@property (nonatomic, strong) SPJob *job;
@property (nonatomic, assign) BOOL didAutoStart;

// 顶部状态条
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) UIProgressView *progress;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UILabel *artifactLabel;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, assign) BOOL showHint;
@end

@implementation SPConsoleViewController

- (instancetype)initWithProject:(SPProject *)project profile:(SPToolchainProfile *)profile {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _project = project;
        _profile = profile;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = [NSString stringWithFormat:@"%@ · %@", self.project.name, self.profile.name];
    self.navigationController.navigationBar.prefersLargeTitles = NO;

    [self buildHeader];

    self.logView = [[SPLogView alloc] init];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.logView.topAnchor constraintEqualToAnchor:self.header.bottomAnchor],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self setupNavigationItems];
    [self appendInfoLines];
}

- (void)appendInfoLines {
    [self.logView appendLine:[NSString stringWithFormat:@"# Spark %@ (%@)", SPVersion.shared.semver, SPVersion.shared.gitDescribe] level:SPLogLevelInfo];
    [self.logView appendLine:[NSString stringWithFormat:@"# 项目   %@", self.project.path] level:SPLogLevelInfo];
    [self.logView appendLine:[NSString stringWithFormat:@"# 目标   %@", self.profile.name] level:SPLogLevelInfo];
    self.logView.maxLines = (NSUInteger)MAX(500, SPSettings.shared.maxLogLines);
    [self.logView appendLine:[NSString stringWithFormat:@"# 选项   %@", [self.project.options displaySummary]] level:SPLogLevelInfo];
    if (self.profile.sdkPath) {
        [self.logView appendLine:[NSString stringWithFormat:@"# SDK    %@", self.profile.sdkName] level:SPLogLevelInfo];
    }
    [self.logView appendLine:@"" level:SPLogLevelOut];
}

#pragma mark - 顶部

- (void)buildHeader {
    self.header = [[UIView alloc] init];
    self.header.backgroundColor = [SPTheme surface];
    self.header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.header];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [SPTheme uiFont:13 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = [SPTheme textDim];
    self.statusLabel.text = @"待编译";
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.timerLabel = [[UILabel alloc] init];
    self.timerLabel.font = [SPTheme monoFont:12];
    self.timerLabel.textColor = [SPTheme textDim];
    self.timerLabel.textAlignment = NSTextAlignmentRight;
    self.timerLabel.text = @"00:00";
    self.timerLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progress.progressTintColor = [SPTheme accent];
    self.progress.trackTintColor = [SPTheme separator];
    self.progress.progress = 0;
    self.progress.translatesAutoresizingMaskIntoConstraints = NO;

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.primaryButton setTitle:@"开始编译" forState:UIControlStateNormal];
    [SPTheme stylePrimaryButton:self.primaryButton];
    [self.primaryButton addTarget:self action:@selector(toggleBuild) forControlEvents:UIControlEventTouchUpInside];
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.secondaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.secondaryButton setTitle:@"预览命令" forState:UIControlStateNormal];
    [SPTheme styleSecondaryButton:self.secondaryButton];
    [self.secondaryButton addTarget:self action:@selector(toggleCommandPreview) forControlEvents:UIControlEventTouchUpInside];
    self.secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = [SPTheme uiFont:12 weight:UIFontWeightRegular];
    self.hintLabel.textColor = [SPTheme warn];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.hidden = YES;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.artifactLabel = [[UILabel alloc] init];
    self.artifactLabel.font = [SPTheme monoFont:11];
    self.artifactLabel.textColor = [SPTheme accent];
    self.artifactLabel.numberOfLines = 2;
    self.artifactLabel.numberOfLines = 2;
    self.artifactLabel.userInteractionEnabled = YES;
    [self.artifactLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showArtifacts)]];
    self.artifactLabel.translatesAutoresizingMaskIntoConstraints = NO;

    for (UIView *v in @[self.statusLabel, self.timerLabel, self.progress, self.primaryButton,
                        self.secondaryButton, self.hintLabel, self.artifactLabel]) {
        [self.header addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:16],
        [self.timerLabel.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.timerLabel.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-16],

        [self.progress.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.progress.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:16],
        [self.progress.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-16],

        [self.primaryButton.topAnchor constraintEqualToAnchor:self.progress.bottomAnchor constant:10],
        [self.primaryButton.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:16],
        [self.primaryButton.heightAnchor constraintEqualToConstant:38],
        [self.primaryButton.widthAnchor constraintEqualToConstant:130],

        [self.secondaryButton.centerYAnchor constraintEqualToAnchor:self.primaryButton.centerYAnchor],
        [self.secondaryButton.leadingAnchor constraintEqualToAnchor:self.primaryButton.trailingAnchor constant:10],
        [self.secondaryButton.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-16],
        [self.secondaryButton.heightAnchor constraintEqualToConstant:38],

        [self.hintLabel.topAnchor constraintEqualToAnchor:self.primaryButton.bottomAnchor constant:8],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:16],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-16],

        [self.artifactLabel.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:6],
        [self.artifactLabel.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:16],
        [self.artifactLabel.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-16],
        [self.artifactLabel.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:-10],
    ]];
}

- (void)setupNavigationItems {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"⋯"
        style:UIBarButtonItemStylePlain target:self action:@selector(showMore)];
}

- (void)showMore {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制完整日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = [self.logView fullText];
        [self.logView showToast:@"已复制到剪贴板"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"保存日志到文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *path = [[SPStore shared] persistLogText:[self.logView fullText] jobId:self.job.jobId ?: @"manual"];
        [self.logView showToast:path ? [NSString stringWithFormat:@"已保存 %@", path.lastPathComponent] : @"保存失败"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self.logView clear];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看产物目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self showArtifacts];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 构建

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.autoStart && !self.didAutoStart) {
        self.didAutoStart = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startBuild];
        });
    }
}

- (void)toggleBuild {
    if (self.session.isRunning) {
        [self stopBuild];
    } else {
        [self startBuild];
    }
}

- (void)startBuild {
    if (self.session.isRunning) return;

    SPBuildOptions *options = self.project.options;
    SPToolchainProfile *profile = self.profile;

    self.statusLabel.text = @"编译中…";
    self.statusLabel.textColor = [SPTheme accent];
    self.progress.progress = 0.06;
    [self.primaryButton setTitle:@"停止" forState:UIControlStateNormal];
    self.primaryButton.backgroundColor = [SPTheme danger];
    self.hintLabel.hidden = YES;
    self.artifactLabel.text = nil;

    NSDate *start = [NSDate date];
    __weak typeof(self) weakSelf = self;
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.timerLabel.text = [SPUtil formatDuration:-[start timeIntervalSinceNow]];
        // 假进度：随时间缓慢爬到 90%
        CGFloat p = self.progress.progress;
        if (p < 0.9) self.progress.progress = p + 0.004;
    }];

    if ([UIApplication sharedApplication].idleTimerDisabled == NO && SPSettings.shared.keepScreenOn) {
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    }

    self.session = [SPBuilder buildProject:self.project options:options profile:profile
        onLine:^(NSString *line, SPLogLevel level) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.logView appendLine:line level:level];
        }
        onFinish:^(SPJob *job) {
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self finishWithJob:job];
        }];
}

- (void)stopBuild {
    if (!self.session.isRunning) return;
    [self.logView appendLine:@"⏹ 正在停止（SIGTERM → SIGKILL）…" level:SPLogLevelErr];
    [self.session cancel];
}

- (void)finishWithJob:(SPJob *)job {
    self.job = job;
    [self.ticker invalidate]; self.ticker = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;

    self.timerLabel.text = [SPUtil formatDuration:job.duration];
    [SPTheme stylePrimaryButton:self.primaryButton];
    [self.primaryButton setTitle:@"重新编译" forState:UIControlStateNormal];
    self.progress.progress = (job.state == SPJobStateSucceeded) ? 1.0 : 0.0;

    if (job.state == SPJobStateSucceeded) {
        self.statusLabel.text = [NSString stringWithFormat:@"✓ 编译成功（%ld 秒）", (long)job.duration];
        self.statusLabel.textColor = [SPTheme accent];
        if (job.artifacts.count) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSString *p in job.artifacts) [names addObject:p.lastPathComponent];
            self.artifactLabel.text = [NSString stringWithFormat:@"📦 %@", [names componentsJoinedByString:@"  ·  "]];
        }
        if (SPSettings.shared.hapticsOnBuildDone) {
            UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
            [g notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
        [self.logView appendLine:@"" level:SPLogLevelOut];
        [self.logView appendLine:[NSString stringWithFormat:@"[ok] 构建成功，用时 %ld 秒", (long)job.duration] level:SPLogLevelStep];
        for (NSString *a in job.artifacts) {
            [self.logView appendLine:[NSString stringWithFormat:@"     产物 → %@", a] level:SPLogLevelStep];
        }
    } else if (job.state == SPJobStateCancelled) {
        self.statusLabel.text = @"已停止";
        self.statusLabel.textColor = [SPTheme warn];
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"✗ 编译失败（exit %ld）", (long)job.exitCode];
        self.statusLabel.textColor = [SPTheme danger];
        self.hintLabel.text = [NSString stringWithFormat:@"💡 %@", job.failureHint ?: @"编译失败，请查看日志。"];
        self.hintLabel.hidden = NO;
        [self.logView appendLine:@"" level:SPLogLevelOut];
        [self.logView appendLine:[NSString stringWithFormat:@"[!] %@", job.failureHint ?: @"构建失败"] level:SPLogLevelErr];
        if (SPSettings.shared.hapticsOnBuildDone) {
            UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
            [g notificationOccurred:UINotificationFeedbackTypeError];
        }
    }

    [[SPStore shared] appendBuildRecord:job];
    if (self.onJobFinished) self.onJobFinished(job);
}

#pragma mark - 命令预览

- (void)toggleCommandPreview {
    NSMutableString *text = [NSMutableString string];
    [text appendString:@"#!/bin/sh\n"];
    [text appendString:[SPBuilder scriptForProject:self.project options:self.project.options
                                            profile:self.profile backupPath:nil]];
    [text appendString:@"\n\n# 上面的脚本可以整段复制到终端执行\n"];

    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"preview.sh"];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    SPEditorViewController *editor = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - 产物

- (void)showArtifacts {
    NSArray *artifacts = self.job.artifacts ?: @[];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"构建产物" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    if (!artifacts.count) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"暂无产物（先编译一次）" style:UIAlertActionStyleDefault handler:nil]];
    }
    for (NSString *a in artifacts) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ · %@", a.lastPathComponent,
                                                          [SPUtil formatBytes:[[NSFileManager defaultManager] attributesOfItemAtPath:a error:NULL].fileSize]]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:a]] applicationActivities:nil];
            av.popoverPresentationController.sourceView = self.view;
            [self presentViewController:av animated:YES completion:nil];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"用文件浏览打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self openBrowserAt:self.project.path];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 100, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openBrowserAt:(NSString *)path {
    SPFileBrowserViewController *vc = [[SPFileBrowserViewController alloc]
        initWithRootPath:path pickMode:NO fileFilters:@[@"deb", @"app"] onPick:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
