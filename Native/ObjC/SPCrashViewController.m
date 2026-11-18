//
//  SPCrashViewController.m
//

#import "SPCrashViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPCrashAnalysis.h"
#import "SPEditorViewController.h"
#import "SPCompat.h"

@interface SPCrashViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPCrashReport *> *reports;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SPCrashViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"崩溃分析";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.estimatedRowHeight = 76;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"xmark.octagon.fill", @"崩溃分析", @"解析 .ips / .crash，给出结论与调用栈", [SPTheme accent], 320);

    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                        target:self action:@selector(pickFile)];
    self.navigationItem.rightBarButtonItem = add;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [SPTheme accent];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self reload];
}

- (void)reload {
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *list = [SPCrashAnalysis scanCommonDirectories];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.spinner stopAnimating];
            self.reports = list;
            [self.table reloadData];
        });
    });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.reports.count ? [NSString stringWithFormat:@"%lu 份崩溃报告", (unsigned long)self.reports.count] : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (self.reports.count) return @"点开看结论与调用栈。扫描的是系统 CrashReporter 目录与 Spark 自己的崩溃记录。";
    return @"没找到崩溃日志。\n\n可以点右上角 ＋ 直接选一个 .ips / .crash 文件。\n"
            "系统的日志通常在 /var/mobile/Library/Logs/CrashReporter。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.reports.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];
    cell.detailTextLabel.numberOfLines = 3;

    SPCrashReport *r = self.reports[ip.row];
    SPCrashFinding *top = r.findings.firstObject;
    NSString *mark = top.severity == SPCrashSeverityError ? @"❌"
                  : (top.severity == SPCrashSeverityWarn ? @"⚠️" : @"ℹ️");

    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", mark, r.appName.length ? r.appName : @"未知应用"];
    cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightMedium];

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm";
    NSString *when = r.crashTime ? [f stringFromDate:r.crashTime] : @"";
    NSString *icon = top.severity == SPCrashSeverityError ? @"xmark.octagon.fill"
                   : (top.severity == SPCrashSeverityWarn ? @"exclamationmark.triangle.fill"
                                                          : @"info.circle.fill");
    cell.imageView.image = [UIImage systemImageNamed:icon];
    cell.imageView.tintColor = top.severity == SPCrashSeverityError ? [SPTheme danger]
                             : (top.severity == SPCrashSeverityWarn ? [SPTheme warn] : [SPTheme info]);

    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@\n%@\n%@",
        r.exceptionType.length ? r.exceptionType : @"?",
        when,
        top.title ?: @"",
        r.version.length ? [NSString stringWithFormat:@"v%@  %@", r.version, r.osVersion] : r.osVersion];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPCrashReport *r = self.reports[ip.row];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:r.summary
        message:[self compactFindings:r] preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"查看完整报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self showFullReport:r];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"复制 Markdown" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIPasteboard.generalPasteboard.string = [SPCrashAnalysis markdownForReport:r];
        [SPMotion hapticSuccess];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除这份日志" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[NSFileManager defaultManager] removeItemAtPath:r.path error:NULL];
        [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = tv;
    [self presentViewController:a animated:YES completion:nil];
}

- (NSString *)compactFindings:(SPCrashReport *)r {
    NSMutableString *s = [NSMutableString string];
    for (SPCrashFinding *f in r.findings) {
        NSString *mark = f.severity == SPCrashSeverityError ? @"❌"
                      : (f.severity == SPCrashSeverityWarn ? @"⚠️" : @"ℹ️");
        [s appendFormat:@"%@ %@\n", mark, f.title];
        if (f.suggestion.length) [s appendFormat:@"   → %@\n", f.suggestion];
        [s appendString:@"\n"];
    }
    return s.length > 900 ? [s substringToIndex:900] : s;
}

- (void)showFullReport:(SPCrashReport *)r {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"crash-%@.md", [SPUtil timestampSlug]]];
    [[SPCrashAnalysis markdownForReport:r] writeToFile:path atomically:YES
                                              encoding:NSUTF8StringEncoding error:NULL];
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:path];
    [self.navigationController pushViewController:e animated:YES];
}

#pragma mark - 导入

- (void)pickFile {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data", @"public.item"] inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    p.allowsMultipleSelection = YES;
    [self.navigationController presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray *newReports = [NSMutableArray array];
    for (NSURL *u in urls) {
        SPCrashReport *r = [SPCrashAnalysis analyzePath:u.path error:NULL];
        if (r) [newReports addObject:r];
    }
    if (!newReports.count) return;
    [SPMotion hapticSuccess];
    NSMutableArray *all = [newReports mutableCopy];
    [all addObjectsFromArray:self.reports ?: @[]];
    self.reports = all;
    [self.table reloadData];
}

@end
