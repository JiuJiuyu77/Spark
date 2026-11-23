//
//  SPLogsViewController.m
//  日志中心：构建 / 注入 / 自检 / 逆向输出 统一在这里看
//

#import "SPLogsViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPStore.h"
#import "SPCompat.h"
#import "SPEditorViewController.h"

@interface SPLogFile : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, strong) NSDate *modified;
@property (nonatomic, copy) NSString *kind;
@end
@implementation SPLogFile


@end

@interface SPLogsViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPLogFile *> *logs;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation SPLogsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"日志";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"doc.text.fill", @"日志", @"保存的构建与运行日志", [SPTheme accent], 320);

    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(reload)];
    // 分享/导出：把日志打包成文件走系统分享面板。
    // 排查问题时最需要的功能 —— 之前只能截屏或复制片段。
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self action:@selector(shareLogs)];
    self.navigationItem.rightBarButtonItems = @[refresh, share];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

/// 根据文件名推断来源，列表里用图标区分
- (NSString *)kindForName:(NSString *)name {
    NSString *n = name.lowercaseString;
    if ([n hasPrefix:@"troll-"]) return @"注入";
    if ([n hasPrefix:@"selfcheck"]) return @"自检";
    if ([n hasPrefix:@"health"]) return @"自检";
    if ([n hasPrefix:@"rev-"]) return @"逆向";
    if ([n hasPrefix:@"inject"]) return @"注入";
    if ([n hasSuffix:@".sh"]) return @"脚本";
    // 构建日志文件名是 <时间戳>-<jobId>.log，jobId 里带 build 的就是构建
    if ([n containsString:@"build"]) return @"构建";
    return @"构建";
}

- (void)reload {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = [[SPStore shared] logsDirectory];
    NSMutableArray<SPLogFile *> *out = [NSMutableArray array];

    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
        NSString *lower = name.lowercaseString;
        if (![lower hasSuffix:@".log"] && ![lower hasSuffix:@".txt"] && ![lower hasSuffix:@".sh"]) continue;

        NSString *p = [dir stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:p error:NULL];

        SPLogFile *f = [SPLogFile new];
        f.name = name;
        f.path = p;
        f.size = [attrs[NSFileSize] unsignedLongLongValue];
        f.modified = attrs[NSFileModificationDate] ?: [NSDate date];
        f.kind = [self kindForName:name];
        [out addObject:f];
    }

    [out sortUsingComparator:^NSComparisonResult(SPLogFile *a, SPLogFile *b) {
        return [b.modified compare:a.modified];
    }];
    self.logs = out;
    [self.table reloadData];
    [self updateEmpty];
}

- (void)updateEmpty {
    if (self.logs.count) { self.table.backgroundView = nil; return; }
    if (!self.emptyLabel) {
        UILabel *l = [[UILabel alloc] init];
        l.text = @"还没有日志\n编译、注入、自检完成后会自动保存在这里";
        l.numberOfLines = 0;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [SPTheme body];
        l.textColor = [SPTheme textDim];
        self.emptyLabel = l;
    }
    self.table.backgroundView = self.emptyLabel;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.logs.count ? [NSString stringWithFormat:@"共 %lu 条", (unsigned long)self.logs.count] : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return self.logs.count ? @"左滑可删除。日志默认保留在 Documents/Workbench/logs。" : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.logs.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];

    SPLogFile *f = self.logs[ip.row];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"MM-dd HH:mm";

    cell.textLabel.text = f.name;
    cell.textLabel.font = [SPTheme mono:12.5];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                                 f.kind, [df stringFromDate:f.modified], [SPUtil formatBytes:f.size]];

    NSString *symbol = @"doc.text";
    if ([f.kind isEqualToString:@"注入"]) symbol = @"syringe";
    else if ([f.kind isEqualToString:@"自检"]) symbol = @"stethoscope";
    else if ([f.kind isEqualToString:@"逆向"]) symbol = @"binoculars";
    else if ([f.kind isEqualToString:@"脚本"]) symbol = @"terminal";
    else symbol = @"hammer";
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = [SPTheme accent];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPLogFile *f = self.logs[ip.row];
    SPEditorViewController *e = [[SPEditorViewController alloc] initWithFilePath:f.path];
    [self.navigationController pushViewController:e animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SPLogFile *f = self.logs[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[NSFileManager defaultManager] removeItemAtPath:f.path error:NULL];
        [self reload];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}


#pragma mark - 导出

- (void)shareLogs {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *logsDir = [[SPStore shared] logsDirectory];
    NSMutableArray<NSURL *> *items = [NSMutableArray array];

    // 1) 主日志 workbench.log —— 构建、注入、自检、崩溃都写在这里
    NSString *main = [logsDir stringByAppendingPathComponent:@"workbench.log"];
    if ([fm fileExistsAtPath:main]) {
        // 复制一份带时间戳的，避免分享面板里名字看不出是哪次
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"spark-%@.log", [SPUtil timestampSlug]]];
        [fm removeItemAtPath:tmp error:NULL];
        if ([[NSData dataWithContentsOfFile:main] writeToFile:tmp atomically:YES]) {
            [items addObject:[NSURL fileURLWithPath:tmp]];
        }
    }

    // 2) 如果当前选中的是某个构建记录，把它一起带上
    NSArray *files = self.logs;
    NSInteger sel = self.table.indexPathForSelectedRow.row;
    if (sel >= 0 && sel < (NSInteger)files.count) {
        NSDictionary *f = files[sel];
        NSString *path = f[@"path"];
        if (path.length && [fm fileExistsAtPath:path]) {
            [items addObject:[NSURL fileURLWithPath:path]];
        }
    }
    // 3) 一个都没有就把整个 logs 目录带上
    if (!items.count) {
        if ([fm fileExistsAtPath:logsDir]) [items addObject:[NSURL fileURLWithPath:logsDir]];
    }

    if (!items.count) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"暂无日志"
            message:@"还没有生成过日志文件。" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    UIActivityViewController *av = [[UIActivityViewController alloc]
        initWithActivityItems:items applicationActivities:nil];
    if (av.popoverPresentationController) {
        av.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    }
    [self presentViewController:av animated:YES completion:nil];
}

@end
