//
//  SPHealthViewController.m —— 主列表
//
//  结构：
//    [一键全测]
//    运行时   (5 项)
//    编译链   (9 项)
//    工具链   (5 项)
//    环境     (4 项)
//
//  每一项：图标 + 标题 + 一句话结论，点进去看命令/输出/诊断。
//

#import "SPHealthViewController.h"
#import "SPHealthCheck.h"
#import "SPTheme.h"
#import "SPCompat.h"
#import "SPGlassKit.h"
#import "SPMotion.h"
#import "SPHealthDetailViewController.h"
#import "SPStore.h"

#pragma mark - 主列表

@interface SPHealthViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) SPGlassHeaderView *header;
@property (nonatomic, strong) SPHealthCheck *checker;
@property (nonatomic, strong) NSMutableArray<SPHealthItem *> *items;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SPHealthItem *> *latestByCategory;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) UILabel *summaryLabel;
@end

@implementation SPHealthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"自检";
    self.view.backgroundColor = [SPTheme background];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.checker = [SPHealthCheck new];
    self.items = [NSMutableArray array];

    self.header = [[SPGlassHeaderView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    [self.header configureWithSymbol:@"stethoscope"
                               title:@"自检"
                            subtitle:@"运行时 · 编译链 · 工具链 · 环境"
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

    // 自动跑一次，省得用户先点一下才知道现状
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self runAll];
    });
}

#pragma mark - 执行

- (void)runAll {
    if (self.running) return;
    self.running = YES;
    [self.items removeAllObjects];
    [self.table reloadData];
    [SPMotion hapticLight];

    __weak typeof(self) weakSelf = self;
    [self.checker runWithItemUpdate:^(SPHealthItem *item) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 同一 title 重复出现时替换，避免反复点「重测」堆一堆
        NSInteger idx = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) {
            if ([self.items[i].title isEqualToString:item.title] &&
                self.items[i].category == item.category) { idx = i; break; }
        }
        if (idx != NSNotFound) self.items[idx] = item;
        else [self.items addObject:item];
        [self.table reloadData];
    } completion:^(SPHealthReport *report) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.running = NO;
        [self.items setArray:report.items];
        [self.table reloadData];

        if (report.allPassed) [SPMotion hapticSuccess];
        else [SPMotion hapticError];

        [self persistReport:report];
    }];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return SPHealthCategoryCount + 1;   // 第一段是操作
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return nil;
    return [SPHealthCheck titleForCategory:(SPHealthCategory)(s - 1)];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != 0) return nil;
    if (self.running) return @"正在检查…";
    if (!self.items.count) return @"点「全部重测」开始。";

    NSInteger fail = 0, warn = 0, pass = 0;
    for (SPHealthItem *i in self.items) {
        if (i.status == SPHealthStatusFail) fail++;
        else if (i.status == SPHealthStatusWarn) warn++;
        else if (i.status == SPHealthStatusPass) pass++;
    }
    if (fail) return [NSString stringWithFormat:@"%ld 项未通过 · %ld 警告 · %ld 通过",
                      (long)fail, (long)warn, (long)pass];
    if (warn) return [NSString stringWithFormat:@"全部可用 · %ld 项警告 · %ld 通过",
                      (long)warn, (long)pass];
    return [NSString stringWithFormat:@"全部通过（%ld 项）", (long)pass];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    SPHealthCategory c = (SPHealthCategory)(s - 1);
    NSInteger n = 0;
    for (SPHealthItem *i in self.items) if (i.category == c) n++;
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                             reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (ip.section == 0) {
        cell.textLabel.text = self.running ? @"检查中…" : @"全部重测";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.running ? [SPTheme textDim] : [SPTheme accent];
        cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightMedium];
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        cell.imageView.tintColor = self.running ? [SPTheme textDim] : [SPTheme accent];
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    SPHealthCategory cat = (SPHealthCategory)(ip.section - 1);
    NSMutableArray *row = [NSMutableArray array];
    for (SPHealthItem *i in self.items) if (i.category == cat) [row addObject:i];
    if (ip.row >= (NSInteger)row.count) return cell;
    SPHealthItem *it = row[ip.row];

    cell.textLabel.text = it.title;
    cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightRegular];
    cell.detailTextLabel.text = it.summary ?: @"";
    cell.detailTextLabel.font = [SPTheme scaled:UIFontTextStyleCaption1 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 2;

    NSString *symbol = @"questionmark.circle";
    UIColor *tint = [SPTheme textDim];
    switch (it.status) {
        case SPHealthStatusPass: symbol = @"checkmark.circle.fill"; tint = [SPTheme success]; break;
        case SPHealthStatusWarn: symbol = @"exclamationmark.triangle.fill"; tint = [SPTheme warn]; break;
        case SPHealthStatusFail: symbol = @"xmark.octagon.fill"; tint = [SPTheme danger]; break;
        case SPHealthStatusSkip: symbol = @"minus.circle"; tint = [SPTheme textDim]; break;
        case SPHealthStatusRunning: symbol = @"clock"; tint = [SPTheme info]; break;
        default: break;
    }
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = tint;
    cell.detailTextLabel.textColor = it.isFailure ? [SPTheme danger] : [SPTheme textDim];
    cell.accessoryType = (it.command.length || it.output.length || it.diagnosis.length)
        ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) { [self runAll]; return; }

    SPHealthCategory cat = (SPHealthCategory)(ip.section - 1);
    NSMutableArray *row = [NSMutableArray array];
    for (SPHealthItem *i in self.items) if (i.category == cat) [row addObject:i];
    if (ip.row >= (NSInteger)row.count) return;

    SPHealthItem *it = row[ip.row];
    if (!it.command.length && !it.output.length && !it.diagnosis.length) return;

    [SPMotion hapticLight];
    SPHealthDetailViewController *d = [[SPHealthDetailViewController alloc] initWithItem:it];
    [self.navigationController pushViewController:d animated:YES];
}


#pragma mark - 落盘

/// 把这次自检写进日志目录，便于「工具 → 日志」里查看或分享给他人。
- (void)persistReport:(SPHealthReport *)report {
    NSMutableString *text = [NSMutableString string];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [text appendFormat:@"Spark 自检报告\n生成时间：%@\n结论：%@\n耗时：%.1f 秒\n\n",
     [df stringFromDate:report.startedAt], report.headline, report.totalSeconds];

    for (NSInteger c = 0; c < SPHealthCategoryCount; c++) {
        NSArray *items = [report itemsInCategory:(SPHealthCategory)c];
        if (!items.count) continue;
        [text appendFormat:@"══ %@ ══\n", [SPHealthCheck titleForCategory:(SPHealthCategory)c]];
        for (SPHealthItem *it in items) {
            NSString *mark = @"?";
            switch (it.status) {
                case SPHealthStatusPass: mark = @"[ok]"; break;
                case SPHealthStatusWarn: mark = @"[!]"; break;
                case SPHealthStatusFail: mark = @"[x]"; break;
                case SPHealthStatusSkip: mark = @"[-]"; break;
                default: break;
            }
            [text appendFormat:@"%@ %@\n", mark, it.title];
            if (it.summary.length) [text appendFormat:@"     结论：%@\n", it.summary];
            if (it.diagnosis.length) {
                NSString *indented = [it.diagnosis stringByReplacingOccurrencesOfString:@"\n"
                                                                             withString:@"\n           "];
                [text appendFormat:@"     诊断：%@\n", indented];
            }
            if (it.command.length) {
                NSString *indented = [it.command stringByReplacingOccurrencesOfString:@"\n"
                                                                           withString:@"\n           "];
                [text appendFormat:@"     命令：%@\n", indented];
            }
            if (it.command.length && it.output.length) {
                [text appendFormat:@"     退出码：%ld · 耗时 %ld ms\n",
                 (long)it.exitCode, (long)it.elapsedMS];
            }
            [text appendString:@"\n"];
        }
    }

    NSString *path = [[SPStore shared] persistLogText:text jobId:@"health"];
    if (path.length) SPLog(@"[自检] 报告已保存：%@", path);
}

@end