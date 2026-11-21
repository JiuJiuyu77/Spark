//
//  SPSelfTestViewController.m
//

#import "SPSelfTestViewController.h"
#import "SPTheme.h"
#import "SPCompat.h"
#import "SPGlassKit.h"
#import "SPSelfTest.h"

@interface SPSelfTestViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) SPGlassHeaderView *header;
@property (nonatomic, strong) NSMutableArray<SPSelfTestStep *> *steps;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
/// 保护 logLines 的串行队列。
/// 后台线程往数组里 addObject，主线程同时读它重绘表格 ——
/// 并发访问 NSMutableArray 会偶发越界崩溃。
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL showLog;
@end

@implementation SPSelfTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"测试构建";
    self.view.backgroundColor = [SPTheme background];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.steps = [NSMutableArray array];
    self.logLines = [NSMutableArray array];
    self.logQueue = dispatch_queue_create("spark.selftest.log", DISPATCH_QUEUE_SERIAL);

    self.header = [[SPGlassHeaderView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    [self.header configureWithSymbol:@"checklist"
                               title:@"测试构建"
                            subtitle:@"自动生成最小 tweak 并完整编译一遍"
                                tint:[SPTheme info]];

    self.table = SPMakeInsetTable(self);
    self.table.dataSource = self;
    self.table.delegate = self;
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    // 至少要有「操作」分区，否则「开始测试」按钮根本不会出现 ——
    // 之前无步骤时只返回 1 个分区，按钮被藏起来了。
    return 2 + (self.showLog && self.logLines.count ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return self.steps.count ? @"检查项" : nil;
    if (s == 1) return @"操作";
    return @"编译日志";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0 && !self.steps.count) {
        return @"会生成一个最小的 tweak 工程（Makefile + Tweak.x + control），\n"
                "用内置工具链完整编译一遍，逐步报告每一步的结果。\n\n"
                "编译失败时会指出是身份、工具链、Theos、SDK 还是编译本身的问题。";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return (NSInteger)self.steps.count;
    if (s == 1) return 2;   // 开始测试 + 查看日志
    __block NSInteger n = 0;
    if (self.logQueue) dispatch_sync(self.logQueue, ^{ n = (NSInteger)self.logLines.count; });
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];

    if (ip.section == 0) {
        SPSelfTestStep *s = self.steps[ip.row];
        cell.textLabel.text = s.title;
        cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightMedium];
        cell.detailTextLabel.text = s.passed ? (s.detail ?: @"通过")
                                             : (s.hint ?: s.detail ?: @"未通过");
        cell.detailTextLabel.font = [SPTheme scaled:UIFontTextStyleCaption1 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = s.passed ? [SPTheme textDim] : [SPTheme danger];
        cell.detailTextLabel.numberOfLines = 3;
        cell.imageView.image = [UIImage systemImageNamed:
            s.passed ? @"checkmark.circle.fill" : @"xmark.octagon.fill"];
        cell.imageView.tintColor = s.passed ? [SPTheme success] : [SPTheme danger];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (ip.section == 1) {
        if (ip.row == 0) {
            cell.textLabel.text = self.running ? @"测试中…" : @"开始测试";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = self.running ? [SPTheme textDim] : [SPTheme accent];
            cell.imageView.image = [UIImage systemImageNamed:@"play.circle.fill"];
            cell.imageView.tintColor = self.running ? [SPTheme textDim] : [SPTheme accent];
        } else {
            cell.textLabel.text = self.showLog ? @"隐藏编译日志" : @"查看编译日志";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [SPTheme info];
            cell.imageView.image = [UIImage systemImageNamed:@"text.alignleft"];
            cell.imageView.tintColor = [SPTheme info];
        }
        cell.detailTextLabel.text = nil;
        return cell;
    }

    __block NSString *ln = @"";
        if (self.logQueue) dispatch_sync(self.logQueue, ^{
            if (ip.row < (NSInteger)self.logLines.count) ln = self.logLines[ip.row];
        });
        cell.textLabel.text = ln;
    cell.textLabel.font = [SPTheme mono:11];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 1) return;

    if (ip.row == 0) {
        if (!self.running) [self start];
        return;
    }
    self.showLog = !self.showLog;
    [self.table reloadData];
}

#pragma mark - 执行

- (void)start {
    // 非 root 时不要「跑一遍再失败」：
    // 访问 SDK / 受保护路径会被直接拒绝，表现是无输出的瞬间退出，
    // 用户完全不知道发生了什么。这里先拦下来并说清楚。
    // 以前这里用 getuid() != 0 直接拦下整个测试。
    // 这是错的：Rein（DSH.app）同样以 uid=501 运行，
    // 它靠的是「运行时文件全在 App 包内 + 子进程用自带 shell」，
    // 并不需要进程本身是 root。
    // 现在不再拦截，改为让测试跑一遍，把身份/权限逐项列出来 ——
    // 真正跑不通的那一步会明确报出来，比一句「需要 root」有用得多。

    self.running = YES;
    [self.steps removeAllObjects];
    if (self.logQueue) dispatch_sync(self.logQueue, ^{ [self.logLines removeAllObjects]; });
    else [self.logLines removeAllObjects];
    [self.table reloadData];

    SPSelfTest *t = [SPSelfTest new];
    __weak typeof(self) weakSelf = self;

    // **必须放到后台队列**
    // runWithLog 内部有 dispatch_semaphore_wait(..., 320 秒)（等编译）
    // 和 20 秒的 shell 启动等待。以前这里直接在主线程调用，
    // 点「测试构建」后界面会卡死最长 5 分钟，看起来像崩溃/无响应。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [t runWithLog:^(NSString *line) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.logLines addObject:line];
            if (self.showLog) [self.table reloadData];
        });
    } stepUpdate:^(SPSelfTestStep *step) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.steps addObject:step];
            [self.table reloadData];
        });
    } completion:^(BOOL ok, NSArray<SPSelfTestStep *> *steps, NSString *summary) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.running = NO;
            [self.table reloadData];
            if (ok) [SPMotion hapticSuccess]; else [SPMotion hapticError];

            UIAlertController *a = [UIAlertController alertControllerWithTitle:
                ok ? @"测试通过" : @"测试未通过"
                message:summary preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        });
    }];
    });   // ← dispatch_async 的闭合
}

@end
