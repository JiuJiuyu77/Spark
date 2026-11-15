//
//  SPShareViewController.m
//  Spark Share Extension —— 让 Spark 出现在其它 App 的「分享」菜单里
//
//  流程：
//   1. 从 NSItemProvider 取出文件副本（支持多个，也支持文件夹→自动打包）
//   2. 写进 App Group 的共享容器：group.com.HuQing.Spark/Incoming/<job>/
//   3. 用 spark://import 拉活主 App，主 App 扫描 Incoming 并清空
//   4. 用户点「完成」结束扩展
//
//  没拿到 App Group（签名不带）时退化为：导出到「文件」App 让用户自己挑位置。
//

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kAppGroup = @"group.com.HuQing.Spark";

@interface SPShareViewController : UIViewController

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) UIButton *diagnoseButton;

@property (nonatomic, assign) NSInteger fileCount;
@property (nonatomic, assign) unsigned long long totalBytes;
@property (nonatomic, strong, nullable) NSError *failure;
@property (nonatomic, copy, nullable) NSString *jobId;
@property (nonatomic, copy, nullable) NSArray<NSURL *> *exportURLs;
@property (nonatomic, assign) BOOL finishing;
@property (nonatomic, assign) BOOL appeared;
@property (nonatomic, copy) NSString *phase;

@end

@implementation SPShareViewController

#pragma mark - 容器

+ (nullable NSURL *)sharedContainer {
    return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
}

- (nullable NSURL *)incomingRoot {
    NSURL *group = [self.class sharedContainer];
    if (!group) return nil;
    NSURL *root = [group URLByAppendingPathComponent:@"Incoming" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root
                           withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700)} error:NULL];
    return root;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"存入 Spark";

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    self.iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"tray.and.arrow.down.fill"]];
    self.iconView.tintColor = [UIColor systemBlueColor];
    self.iconView.hidden = YES;
    [stack addArrangedSubview:self.iconView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];
    [stack addArrangedSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"正在接收文件…";
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:self.statusLabel];

    self.openButton = [self filledButton:@"打开 Spark" symbol:@"arrow.up.forward.app" action:@selector(openHost)];
    self.openButton.hidden = YES;
    [stack addArrangedSubview:self.openButton];

    self.exportButton = [self filledButton:@"选择保存位置" symbol:@"folder" action:@selector(exportFiles)];
    self.exportButton.hidden = YES;
    [stack addArrangedSubview:self.exportButton];

    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.doneButton setTitle:@"完成" forState:UIControlStateNormal];
    [self.doneButton addTarget:self action:@selector(doneShare) forControlEvents:UIControlEventTouchUpInside];
    self.doneButton.hidden = YES;
    [stack addArrangedSubview:self.doneButton];

    self.diagnoseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.diagnoseButton setTitle:@"接收诊断" forState:UIControlStateNormal];
    self.diagnoseButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    [self.diagnoseButton addTarget:self action:@selector(showDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    self.diagnoseButton.hidden = YES;
    [stack addArrangedSubview:self.diagnoseButton];

    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],
    ]];

    [self receive];
}

- (UIButton *)filledButton:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.title = title;
    cfg.image = [UIImage systemImageNamed:symbol];
    cfg.imagePadding = 8;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    b.configuration = cfg;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.appeared = YES;
    // 已经收好文件但还没拉活主 App，这里补一次
    if (self.jobId && !self.finishing) [self openHost];
}

#pragma mark - 接收

- (void)receive {
    self.phase = @"collectProviders";

    NSMutableArray<NSItemProvider *> *providers = [NSMutableArray array];
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *p in item.attachments) {
            if ([self providerHasFile:p]) [providers addObject:p];
        }
    }

    if (!providers.count) {
        self.phase = @"noProviders";
        [self showRecovery:@"没有可接收的文件。\n请在「文件」里选择文件后再分享到 Spark（网页链接不支持）。"];
        return;
    }
    if (providers.count > 20) {
        self.phase = @"tooMany";
        [self showRecovery:@"一次最多接收 20 个文件，请分批分享。"];
        return;
    }

    NSURL *root = [self incomingRoot];
    BOOL hasGroup = root != nil;
    NSString *job = NSUUID.UUID.UUIDString;
    NSURL *staging = hasGroup
        ? [root URLByAppendingPathComponent:[@".receiving-" stringByAppendingString:job] isDirectory:YES]
        : [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:job] isDirectory:YES];

    NSError *err = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:staging
                               withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700)} error:&err]) {
        self.phase = @"stagingFailed";
        [self showRecovery:err.localizedDescription];
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    NSLock *lock = [NSLock new];
    NSMutableArray<NSURL *> *saved = [NSMutableArray array];

    for (NSItemProvider *provider in providers) {
        dispatch_group_enter(group);
        [self loadFileFrom:provider stagingDir:staging childIndex:saved.count completion:^(NSURL *url, NSString *name, NSError *e) {
            [lock lock];
            if (url && !e) {
                self.fileCount += 1;
                NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:NULL];
                self.totalBytes += [a[NSFileSize] unsignedLongLongValue];
                [saved addObject:url];
            } else if (e) {
                self.failure = e;
            }
            [lock unlock];
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating];

        if (self.failure) {
            self.phase = @"receiveFailed";
            [NSFileManager.defaultManager removeItemAtURL:staging error:NULL];
            [self showRecovery:self.failure.localizedDescription];
            return;
        }

        if (hasGroup) {
            NSURL *ready = [root URLByAppendingPathComponent:job isDirectory:YES];
            NSError *moveErr = nil;
            if (![[NSFileManager defaultManager] moveItemAtURL:staging toURL:ready error:&moveErr]) {
                self.phase = @"publishFailed";
                [self showRecovery:moveErr.localizedDescription];
                return;
            }
            self.phase = @"readyInGroup";
            self.jobId = job;
            self.statusLabel.text = [NSString stringWithFormat:@"已接收 %ld 个文件（%@）\n正在打开 Spark…",
                                     (long)self.fileCount, [NSByteCountFormatter stringFromByteCount:(long long)self.totalBytes
                                                                                           countStyle:NSByteCountFormatterCountStyleFile]];
            self.iconView.hidden = NO;
            [self openHost];
        } else {
            // 没有 App Group 权限：只能让用户手动导出
            self.phase = @"awaitingManualExport";
            self.exportURLs = saved;
            self.iconView.hidden = NO;
            self.statusLabel.text = [NSString stringWithFormat:
                @"已准备 %ld 个文件\n\n点「选择保存位置」，保存到「我的 iPhone → Spark」，再打开 Spark 会自动识别。\n"
                 "（当前签名没带 App Group，所以需要手动存一次。）", (long)self.fileCount];
            self.exportButton.hidden = NO;
            self.doneButton.hidden = NO;
            [self.doneButton setTitle:@"取消接收" forState:UIControlStateNormal];
            self.diagnoseButton.hidden = NO;
        }
    });
}

/// 判断 provider 里有文件（而不是纯文本/URL）
- (BOOL)providerHasFile:(NSItemProvider *)p {
    if ([p hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier]) return YES;
    if ([p hasItemConformingToTypeIdentifier:UTTypeData.identifier]) return YES;
    if ([p hasItemConformingToTypeIdentifier:UTTypeFolder.identifier]) return YES;
    if ([p hasItemConformingToTypeIdentifier:@"public.zip-archive"]) return YES;
    return NO;
}

/// 取出单个文件副本，复制到 staging
- (void)loadFileFrom:(NSItemProvider *)provider
          stagingDir:(NSURL *)staging
          childIndex:(NSInteger)index
          completion:(void (^)(NSURL *_Nullable url, NSString *_Nullable name, NSError *_Nullable error))completion {

    NSString *typeId = UTTypeFileURL.identifier;
    if ([provider hasItemConformingToTypeIdentifier:UTTypeFolder.identifier]) {
        typeId = UTTypeFolder.identifier;
    }

    [provider loadItemForTypeIdentifier:typeId options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        // item 声明成 id<NSSecureCoding>，协议不带 NSObject 方法，先转成 id 再判断
        id obj = (id)item;
        NSURL *src = nil;
        if ([obj isKindOfClass:NSURL.class]) src = (NSURL *)obj;
        else if ([obj isKindOfClass:NSData.class]) {
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [(NSData *)obj writeToFile:tmp atomically:YES];
            src = [NSURL fileURLWithPath:tmp];
        }
        if (!src) {
            NSError *e = [NSError errorWithDomain:@"Spark.Share" code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"来源 App 没有提供文件副本。"}];
            completion(nil, nil, e);
            return;
        }

        NSString *name = provider.suggestedName.length ? provider.suggestedName : src.lastPathComponent;
        if (!name.length) name = @"SharedFile";

        // 每个文件放自己的子目录，避免重名覆盖
        NSString *childName = [NSString stringWithFormat:@"%02ld-%@", (long)index, name];
        NSURL *dest = [staging URLByAppendingPathComponent:childName];

        NSError *err = nil;
        BOOL isDir = NO;
        [NSFileManager.defaultManager fileExistsAtPath:src.path isDirectory:&isDir];

        if (isDir) {
            // 文件夹：整目录复制，主 App 导入时会当项目候选处理
            if (![[NSFileManager defaultManager] copyItemAtPath:src.path toPath:dest.path error:&err]) {
                completion(nil, nil, err);
                return;
            }
            completion(dest, childName, nil);
            return;
        }

        if (![NSFileManager.defaultManager copyItemAtPath:src.path toPath:dest.path error:&err]) {
            completion(nil, nil, err);
            return;
        }
        completion(dest, childName, nil);
    }];
}


#pragma mark - 拉活主 App

- (void)openHost {
    self.openButton.hidden = YES;
    self.doneButton.hidden = !self.jobId;
    [self.doneButton setTitle:@"完成" forState:UIControlStateNormal];
    [self.spinner startAnimating];

    NSURL *url = [NSURL URLWithString:@"spark://import"];
    NSURL *group = [self.class sharedContainer];
    if (!group && !self.jobId) {
        [self showRecovery:@"文件已接收，但需要手动保存到 Spark。"];
        return;
    }

    // 扩展里不能直接 openURL，需要沿 responder 链找到 UIApplication，
    // 或退回 extensionContext（部分系统支持）
    __weak typeof(self) weakSelf = self;
    BOOL (^handler)(BOOL) = ^BOOL(BOOL ok) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return ok;
        if (ok) {
            [self doneShare];
        } else {
            [self.spinner stopAnimating];
            self.statusLabel.text = @"文件已接收。\n若没有自动跳转，请从桌面打开 Spark，文件会在「收件箱」里。";
            self.iconView.hidden = NO;
            self.openButton.hidden = NO;
            self.doneButton.hidden = NO;
            self.diagnoseButton.hidden = NO;
        }
        return ok;
    };

    UIResponder *responder = self;
    NSInteger hops = 0;
    NSMutableSet *visited = [NSMutableSet set];
    while (responder && hops++ < 64) {
        NSValue *key = [NSValue valueWithNonretainedObject:responder];
        if ([visited containsObject:key]) break;
        [visited addObject:key];
        if ([responder isKindOfClass:UIApplication.class]) {
            [(UIApplication *)responder openURL:url options:@{} completionHandler:^(BOOL success) {
                handler(success);
            }];
            return;
        }
        responder = responder.nextResponder;
    }

    // 兜底：extensionContext
    if (self.extensionContext) {
        [self.extensionContext openURL:url completionHandler:^(BOOL success) { handler(success); }];
    } else {
        handler(NO);
    }
}

#pragma mark - 导出 / 完成

- (void)exportFiles {
    if (!self.exportURLs.count) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForExportingURLs:self.exportURLs asCopy:YES];
    picker.shouldShowFileExtensions = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)doneShare {
    if (self.finishing) return;
    self.finishing = YES;
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

#pragma mark - 状态提示

- (void)showRecovery:(NSString *)message {
    [self.spinner stopAnimating];
    self.iconView.hidden = NO;
    self.iconView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
    self.iconView.tintColor = [UIColor systemOrangeColor];
    self.statusLabel.text = message;
    self.statusLabel.textColor = [UIColor labelColor];
    self.doneButton.hidden = NO;
    [self.doneButton setTitle:@"关闭" forState:UIControlStateNormal];
    self.diagnoseButton.hidden = NO;
}

- (void)showDiagnostics {
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"phase"] = self.phase ?: @"unknown";
    report[@"appGroup"] = [self.class sharedContainer] != nil ? @"可写" : @"不可用（签名缺 App Group）";
    report[@"files"] = @(self.fileCount);
    report[@"bytes"] = @(self.totalBytes);
    report[@"jobId"] = self.jobId ?: @"";
    report[@"system"] = [NSProcessInfo processInfo].operatingSystemVersionString;
    if (self.failure) report[@"error"] = self.failure.localizedDescription ?: @"";
    NSData *d = [NSJSONSerialization dataWithJSONObject:report
                                               options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    NSString *text = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"诊断读取失败";

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"接收诊断" message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIPasteboard.generalPasteboard.string = text;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
