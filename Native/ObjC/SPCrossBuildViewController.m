//
//  SPCrossBuildViewController.m
//

#import "SPCrossBuildViewController.h"
#import "SPTheme.h"
#import "SPCompat.h"
#import "SPGlassKit.h"
#import "SPSession.h"
#import "SPStore.h"

@interface SPCrossBuildViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy, nullable) NSString *sourcePath;
@property (nonatomic, copy, nullable) NSString *sdkRoot;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) SPGlassHeaderView *header;
@end

@implementation SPCrossBuildViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"快速编译";
    self.view.backgroundColor = [SPTheme background];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.logLines = [NSMutableArray array];

    self.header = [[SPGlassHeaderView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    [self.header configureWithSymbol:@"bolt.horizontal.circle.fill"
                               title:@"快速编译"
                            subtitle:@"不依赖 Theos：单文件 .m → 已签名 dylib"
                                tint:[SPTheme info]];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    CGSize sz = [self.header systemLayoutSizeFittingSize:CGSizeMake(320, UIViewNoIntrinsicMetric)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.header.frame = CGRectMake(0, 0, 320, MAX(96, sz.height));
    self.table.tableHeaderView = self.header;
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"输入";
    if (s == 1) return @"开始";
    return self.logLines.count ? @"输出" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"只支持单个 .m 文件。含 Logos（.x）或多文件的完整工程请用「项目」页的常规编译。\n"
                "SDK 留空时会自动在已展开的工具链里找 libSystem.tbd。";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;
    if (s == 1) return 1;
    return (NSInteger)self.logLines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];

    if (ip.section == 0) {
        if (ip.row == 0) {
            cell.textLabel.text = @"源文件";
            cell.detailTextLabel.text = self.sourcePath.length
                ? self.sourcePath.lastPathComponent
                : @"点这里选择 .m 文件";
            cell.imageView.image = [UIImage systemImageNamed:@"doc.text"];
            cell.imageView.tintColor = [SPTheme accent];
        } else {
            cell.textLabel.text = @"SDK 根目录";
            cell.detailTextLabel.text = self.sdkRoot.length
                ? self.sdkRoot.lastPathComponent
                : @"自动查找（可留空）";
            cell.imageView.image = [UIImage systemImageNamed:@"shippingbox"];
            cell.imageView.tintColor = [SPTheme textDim];
        }
        cell.detailTextLabel.textColor = [SPTheme textDim];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (ip.section == 1) {
        cell.textLabel.text = self.running ? @"编译中…" : @"开始编译";
        cell.textLabel.textColor = self.sourcePath.length ? [SPTheme accent] : [SPTheme textDim];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.imageView.image = [UIImage systemImageNamed:@"hammer.fill"];
        cell.imageView.tintColor = self.sourcePath.length ? [SPTheme accent] : [SPTheme textDim];
        cell.selectionStyle = self.sourcePath.length ? UITableViewCellSelectionStyleDefault
                                                     : UITableViewCellSelectionStyleNone;
        return cell;
    }

    cell.textLabel.text = self.logLines[ip.row];
    cell.textLabel.font = [SPTheme mono:11];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        if (ip.row == 0) [self pickSource];
        else [self pickSDK];
        return;
    }
    if (ip.section == 1) {
        if (!self.sourcePath.length || self.running) return;
        [self startBuild];
    }
}

#pragma mark - 选择

- (void)pickSource {
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.source-code", @"public.item"]
                                                               inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)pickSDK {
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"]
                                                               inMode:UIDocumentPickerModeOpen];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    BOOL dir = NO;
    [NSFileManager.defaultManager fileExistsAtPath:u.path isDirectory:&dir];
    if (dir) {
        self.sdkRoot = u.path;
        [self appendLog:[NSString stringWithFormat:@"SDK：%@", u.path]];
    } else {
        self.sourcePath = u.path;
        [self appendLog:[NSString stringWithFormat:@"源文件：%@", u.lastPathComponent]];
    }
    [self.table reloadData];
}

#pragma mark - 编译

- (void)startBuild {
    self.running = YES;
    [self.logLines removeAllObjects];
    [self.table reloadData];

    NSString *src = self.sourcePath;
    NSString *outDir = [[[SPStore shared] baseDirectory] stringByAppendingPathComponent:@"cross-out"];
    [NSFileManager.defaultManager createDirectoryAtPath:outDir
                            withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *out = [outDir stringByAppendingPathComponent:
                     [src.lastPathComponent.stringByDeletingPathExtension stringByAppendingPathExtension:@"dylib"]];

    // 把脚本复制到临时目录再执行（避免沙盒里脚本不可执行的问题）
    NSString *scriptSrc = [[[NSBundle mainBundle] bundlePath]
                           stringByAppendingPathComponent:@"tools/spark-cross-build.sh"];
    NSString *script = [NSTemporaryDirectory() stringByAppendingPathComponent:@"spark-cross.sh"];
    (void)scriptSrc;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *body = [NSString stringWithContentsOfFile:scriptSrc
                                               encoding:NSUTF8StringEncoding error:NULL];

    if (!body.length) {
        [self finishWithMessages:@[@"[x] 包内缺少 tools/spark-cross-build.sh",
                                   @"这是构建配置问题：CI 打包时没有把 tools 目录放进来。"]];
        return;
    }
    [body writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:script error:NULL];

    NSMutableArray *args = [NSMutableArray arrayWithObjects:src, out, nil];
    if (self.sdkRoot.length) [args addObject:self.sdkRoot];

    NSMutableString *cmd = [NSMutableString stringWithFormat:@"sh %@", [SPUtil shellQuote:script]];
    for (NSString *a in args) [cmd appendFormat:@" %@", [SPUtil shellQuote:a]];

    SPSession *s = [[SPSession alloc] initWithEnvironment:@{}
                                          workingDirectory:outDir];
    s.timeout = 180;
    __weak typeof(self) weakSelf = self;
    NSString *outPath = [out copy];
    __block NSMutableArray *collected = [NSMutableArray array];
    s.onLine = ^(NSString *line, SPLogLevel lv) {
        @synchronized (collected) { [collected addObject:line ?: @""]; }
    };
    s.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSArray *lines = nil;
        @synchronized (collected) { lines = [collected copy]; }
        NSMutableArray *msgs = [lines mutableCopy] ?: [NSMutableArray array];
        if (r.exitCode == 0) {
            [msgs addObject:[NSString stringWithFormat:@"[ok] 产物：%@", outPath.lastPathComponent]];
        } else {
            [out addObject:[NSString stringWithFormat:@"[x] 失败，退出码 %ld", (long)r.exitCode]];
        }
        [self finishWithMessages:msgs];
    };
    [s runShell:cmd];
}

- (void)appendLog:(NSString *)line {
    if (!line) return;
    [self.logLines addObject:line];
    [self.table reloadData];
}

- (void)finishWithMessages:(NSArray<NSString *> *)messages {
    self.running = NO;
    [self.logLines setArray:messages ?: @[]];
    [self.table reloadData];

    if ([messages.lastObject hasPrefix:@"[ok]"]) [SPMotion hapticSuccess];
    else [SPMotion hapticError];
}

@end
