//
//  SPConsoleViewController.m
//  构建控制台 —— HIG：状态卡 + 日志 + 毛玻璃底部操作条
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
#import "SPModels.h"
#import "SPToolchain.h"

@interface SPConsoleViewController ()
@property (nonatomic, strong) SPProject *project;
@property (nonatomic, strong) SPToolchainProfile *profile;
@property (nonatomic, strong) SPLogView *logView;
@property (nonatomic, strong) SPSession *session;
@property (nonatomic, strong) SPJob *job;
@property (nonatomic, assign) BOOL didAutoStart;

@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIImageView *statusIcon;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIProgressView *progress;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIStackView *artifactStack;

@property (nonatomic, strong) SPGlassBar *actionBar;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;

@property (nonatomic, strong) NSTimer *ticker;
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
    self.title = self.project.name;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self buildActionBar];
    [self buildStatusCard];
    [self buildLogView];
    [self setupNavItems];
    [self appendInfoLines];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.autoStart && !self.didAutoStart) {
        self.didAutoStart = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startBuild];
        });
    }
}

#pragma mark - 状态卡

- (void)buildStatusCard {
    SPCardView *card = [[SPCardView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];
    self.statusCard = card;

    self.statusIcon = [[UIImageView alloc] init];
    self.statusIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.statusIcon.tintColor = [SPTheme textDim];
    self.statusIcon.image = [UIImage systemImageNamed:@"hammer"];
    self.statusIcon.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
    self.statusLabel.textColor = [SPTheme text];
    self.statusLabel.text = @"待编译";
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.timerLabel = [[UILabel alloc] init];
    self.timerLabel.font = [SPTheme mono:12];
    self.timerLabel.textColor = [SPTheme textDim];
    self.timerLabel.textAlignment = NSTextAlignmentRight;
    self.timerLabel.text = @"00:00";
    self.timerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.timerLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.font = [SPTheme caption];
    self.detailLabel.textColor = [SPTheme textDim];
    self.detailLabel.numberOfLines = 2;
    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", self.profile.name,
                             [self.project.options displaySummary]];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progress.progressTintColor = [SPTheme accent];
    self.progress.progress = 0;
    self.progress.translatesAutoresizingMaskIntoConstraints = NO;

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.font = [SPTheme caption];
    self.hintLabel.textColor = [SPTheme warn];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.hidden = YES;
    self.hintLabel.alpha = 0;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    for (UIView *v in @[self.statusIcon, self.statusLabel, self.timerLabel,
                        self.detailLabel, self.progress, self.hintLabel]) {
        [card.contentView addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.statusIcon.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [self.statusIcon.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [self.statusIcon.widthAnchor constraintEqualToConstant:22],
        [self.statusIcon.heightAnchor constraintEqualToConstant:22],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusIcon.trailingAnchor constant:8],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.statusIcon.centerYAnchor],
        [self.timerLabel.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.timerLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.statusLabel.trailingAnchor constant:8],
        [self.timerLabel.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],

        [self.detailLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:6],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],

        [self.progress.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:10],
        [self.progress.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [self.progress.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],

        [self.hintLabel.topAnchor constraintEqualToAnchor:self.progress.bottomAnchor constant:10],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor],
    ]];

    NSLayoutConstraint *pin = [card.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8];
    NSLayoutConstraint *lead = [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16];
    NSLayoutConstraint *trail = [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16];
    [NSLayoutConstraint activateConstraints:@[pin, lead, trail]];
}

#pragma mark - 日志

- (void)buildLogView {
    self.logView = [[SPLogView alloc] init];
    self.logView.maxLines = (NSUInteger)MAX(500, SPSettings.shared.maxLogLines);
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [SPTheme round:self.logView radius:12];
    self.logView.clipsToBounds = YES;
    [self.view addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.logView.topAnchor constraintEqualToAnchor:self.statusCard.bottomAnchor constant:12],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.actionBar.topAnchor constant:-12],
    ]];
}

- (void)appendInfoLines {
    [self.logView appendLine:[NSString stringWithFormat:@"Spark %@ (%@)", SPVersion.shared.semver, SPVersion.shared.gitDescribe] level:SPLogLevelInfo];
    [self.logView appendLine:[NSString stringWithFormat:@"项目  %@", self.project.path] level:SPLogLevelInfo];
    [self.logView appendLine:[NSString stringWithFormat:@"目标  %@", self.profile.name] level:SPLogLevelInfo];
    [self.logView appendLine:[NSString stringWithFormat:@"选项  %@", [self.project.options displaySummary]] level:SPLogLevelInfo];
    if (self.profile.sdkPath) {
        [self.logView appendLine:[NSString stringWithFormat:@"SDK   %@", self.profile.sdkName] level:SPLogLevelInfo];
    }
    [self.logView appendLine:@"" level:SPLogLevelOut];
}

#pragma mark - 底部操作条（毛玻璃）

- (void)buildActionBar {
    self.actionBar = [[SPGlassBar alloc] init];
    [self.view addSubview:self.actionBar];

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.primaryButton setTitle:@"开始编译" forState:UIControlStateNormal];
    [SPTheme stylePrimaryButton:self.primaryButton];
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.primaryButton addTarget:self action:@selector(toggleBuild) forControlEvents:UIControlEventTouchUpInside];
    [self.primaryButton addTarget:self action:@selector(pressDown:) forControlEvents:UIControlEventTouchDown];
    [self.primaryButton addTarget:self action:@selector(pressUp:) forControlEvents:UIControlEventTouchUpInside];

    self.secondaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.secondaryButton setTitle:@"查看命令" forState:UIControlStateNormal];
    [SPTheme styleSecondaryButton:self.secondaryButton];
    self.secondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.secondaryButton addTarget:self action:@selector(toggleCommandPreview) forControlEvents:UIControlEventTouchUpInside];

    [self.actionBar.contentView addSubview:self.primaryButton];
    [self.actionBar.contentView addSubview:self.secondaryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.actionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.actionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.actionBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.primaryButton.topAnchor constraintEqualToAnchor:self.actionBar.contentView.topAnchor constant:10],
        [self.primaryButton.leadingAnchor constraintEqualToAnchor:self.actionBar.contentView.leadingAnchor constant:16],
        [self.primaryButton.heightAnchor constraintEqualToConstant:48],
        [self.primaryButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],

        [self.secondaryButton.centerYAnchor constraintEqualToAnchor:self.primaryButton.centerYAnchor],
        [self.secondaryButton.leadingAnchor constraintEqualToAnchor:self.primaryButton.trailingAnchor constant:10],
        [self.secondaryButton.trailingAnchor constraintEqualToAnchor:self.actionBar.contentView.trailingAnchor constant:-16],
        [self.secondaryButton.heightAnchor constraintEqualToConstant:48],
        [self.secondaryButton.widthAnchor constraintEqualToConstant:110],
    ]];
    [self.primaryButton setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)pressDown:(UIButton *)b {
    [SPMotion pressDown:b];
}

- (void)pressUp:(UIButton *)b {
    [SPMotion pressUp:b];
}

- (void)setupNavItems {
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(showMore)];
    more.accessibilityLabel = @"更多";
    self.navigationItem.rightBarButtonItem = more;
}

- (void)showMore {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制完整日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = [self.logView fullText];
        [self.logView showToast:@"已复制到剪贴板"];
        [SPMotion hapticSuccess];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"保存日志到文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *path = [[SPStore shared] persistLogText:[self.logView fullText] jobId:self.job.jobId ?: @"manual"];
        [self.logView showToast:path ? [NSString stringWithFormat:@"已保存 %@", path.lastPathComponent] : @"保存失败"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self.logView clear];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"打开产物目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self revealArtifacts];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 构建

- (void)toggleBuild {
    if (self.session.isRunning) [self stopBuild];
    else [self startBuild];
}

- (void)startBuild {
    if (self.session.isRunning) return;
    [SPMotion hapticLight];

    [self setStatus:@"编译中…" symbol:@"gearshape.2" color:[SPTheme accent]];
    [self.primaryButton setTitle:@"停止" forState:UIControlStateNormal];
    [SPTheme styleDestructiveButton:self.primaryButton];
    [self hideHint];
    [self clearArtifacts];
    [SPMotion spring:^{ self.progress.progress = 0.05; }];

    NSDate *start = [NSDate date];
    __weak typeof(self) weakSelf = self;
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *t) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.timerLabel.text = [SPUtil formatDuration:-[start timeIntervalSinceNow]];
        if (self.progress.progress < 0.9) {
            [SPMotion animate:^{ self.progress.progress += 0.006; } duration:0.4];
        }
    }];

    if (SPSettings.shared.keepScreenOn) [UIApplication sharedApplication].idleTimerDisabled = YES;

    self.session = [SPBuilder buildProject:self.project options:self.project.options profile:self.profile
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
    [SPMotion hapticLight];
    [self.logView appendLine:@"正在停止…" level:SPLogLevelErr];
    [self.session cancel];
}

- (void)finishWithJob:(SPJob *)job {
    self.job = job;
    [self.ticker invalidate];
    self.ticker = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    self.timerLabel.text = [SPUtil formatDuration:job.duration];

    [self.primaryButton setTitle:@"重新编译" forState:UIControlStateNormal];
    [SPTheme stylePrimaryButton:self.primaryButton];

    if (job.state == SPJobStateSucceeded) {
        [SPMotion spring:^{ self.progress.progress = 1.0; }];
        [self setStatus:[NSString stringWithFormat:@"编译成功 · %ld 秒", (long)job.duration]
                symbol:@"checkmark.circle.fill" color:[SPTheme success]];
        [SPMotion pop:self.statusIcon];
        [SPMotion hapticSuccess];
        [self.logView appendLine:@"" level:SPLogLevelOut];
        [self.logView appendLine:[NSString stringWithFormat:@"[ok] 用时 %ld 秒", (long)job.duration] level:SPLogLevelStep];
        for (NSString *a in job.artifacts) {
            [self.logView appendLine:[NSString stringWithFormat:@"     产物 → %@", a] level:SPLogLevelStep];
        }
        [self showArtifacts:job.artifacts];
    } else if (job.state == SPJobStateCancelled) {
        [SPMotion animate:^{ self.progress.progress = 0; } duration:0.2];
        [self setStatus:@"已停止" symbol:@"stop.circle" color:[SPTheme warn]];
    } else {
        [SPMotion animate:^{ self.progress.progress = 0; } duration:0.2];
        [self setStatus:[NSString stringWithFormat:@"编译失败 · exit %ld", (long)job.exitCode]
                symbol:@"xmark.octagon.fill" color:[SPTheme danger]];
        [SPMotion hapticError];
        [self showHint:job.failureHint ?: @"编译失败，请查看日志最后几行。"];
        [self.logView appendLine:@"" level:SPLogLevelOut];
        [self.logView appendLine:[NSString stringWithFormat:@"[!] %@", job.failureHint ?: @"构建失败"] level:SPLogLevelErr];
    }

    [[SPStore shared] appendBuildRecord:job];
    if (self.onJobFinished) self.onJobFinished(job);
}

- (void)setStatus:(NSString *)text symbol:(NSString *)symbol color:(UIColor *)color {
    [SPMotion animate:^{
        self.statusLabel.text = text;
        self.statusLabel.textColor = color;
        self.statusIcon.image = [UIImage systemImageNamed:symbol];
        self.statusIcon.tintColor = color;
    } duration:0.2];
}

- (void)showHint:(NSString *)hint {
    self.hintLabel.text = [NSString stringWithFormat:@"建议：%@", hint];
    self.hintLabel.hidden = NO;
    [SPMotion appear:^{ self.hintLabel.alpha = 1.0; }];
}

- (void)hideHint {
    if (self.hintLabel.hidden) return;
    [SPMotion disappear:^{ self.hintLabel.alpha = 0; } completion:^{ self.hintLabel.hidden = YES; }];
}

#pragma mark - 产物

- (void)clearArtifacts {
    [self.artifactStack removeFromSuperview];
    self.artifactStack = nil;
}

- (void)showArtifacts:(NSArray<NSString *> *)artifacts {
    [self clearArtifacts];
    if (!artifacts.count) return;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusCard addSubview:stack];

    for (NSString *path in artifacts) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        unsigned long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL].fileSize;
        UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
        cfg.title = [NSString stringWithFormat:@"  %@ · %@", path.lastPathComponent, [SPUtil formatBytes:size]];
        cfg.image = [UIImage systemImageNamed:@"shippingbox.fill"];
        cfg.imagePadding = 8;
        cfg.baseBackgroundColor = [[SPTheme accent] colorWithAlphaComponent:0.12];
        cfg.baseForegroundColor = [SPTheme accent];
        cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(10, 12, 10, 12);
        row.configuration = cfg;
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        row.tag = [artifacts indexOfObject:path];
        [row addTarget:self action:@selector(shareArtifact:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:row];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.statusCard.bottomAnchor constant:8],
        [stack.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor],
    ]];
    self.artifactStack = stack;
    [SPMotion appear:^{ stack.alpha = 1; }];

    // 让日志区跟着往下挪
    [self.view setNeedsLayout];
}

- (void)shareArtifact:(UIButton *)sender {
    if (!self.job.artifacts.count) return;
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.job.artifacts.count) return;
    NSString *path = self.job.artifacts[idx];
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                                                    applicationActivities:nil];
    av.popoverPresentationController.sourceView = sender;
    av.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:av animated:YES completion:nil];
    [SPMotion hapticLight];
}

- (void)revealArtifacts {
    SPFileBrowserViewController *vc = [[SPFileBrowserViewController alloc]
        initWithRootPath:self.project.path pickMode:NO fileFilters:@[@"deb", @"app"] onPick:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 命令预览

- (void)toggleCommandPreview {
    NSMutableString *text = [NSMutableString string];
    [text appendString:@"#!/bin/sh\n"];
    [text appendString:[SPBuilder scriptForProject:self.project options:self.project.options
                                            profile:self.profile backupPath:nil]];
    [text appendString:@"\n# 上面这段可以整段复制到终端里复现\n"];

    NSString *path = [[[SPStore shared] logsDirectory] stringByAppendingPathComponent:@"preview.sh"];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    SPEditorViewController *editor = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:editor animated:YES];
}

@end
