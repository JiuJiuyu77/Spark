//
//  SPStorageViewController.m
//

#import "SPStorageViewController.h"
#import "SPTheme.h"
#import "SPStorage.h"
#import "SPAnimationKit.h"
#import "SPCompat.h"
#import "SPFileBrowserViewController.h"

@interface SPStorageViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPStorageEntry *> *entries;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *diskLabel;
@end

@implementation SPStorageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"存储空间";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.diskLabel = [[UILabel alloc] init];
    self.diskLabel.font = [SPTheme scaled:UIFontTextStyleSubheadline weight:UIFontWeightMedium];
    self.diskLabel.textColor = [SPTheme textDim];
    self.diskLabel.textAlignment = NSTextAlignmentCenter;
    self.diskLabel.numberOfLines = 2;
    self.diskLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.diskLabel];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"s"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.diskLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [self.diskLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SPSpaceL],
        [self.diskLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SPSpaceL],
        [self.table.topAnchor constraintEqualToAnchor:self.diskLabel.bottomAnchor constant:4],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [SPTheme accent];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    [self reload];
}

- (void)reload {
    [self.spinner startAnimating];
    NSDictionary *disk = [[SPStorage shared] diskSpace];
    unsigned long long total = [disk[@"total"] unsignedLongLongValue];
    unsigned long long free = [disk[@"free"] unsignedLongLongValue];
    self.diskLabel.text = [NSString stringWithFormat:@"设备可用 %@ / 共 %@",
                           [SPUtil formatBytes:free], [SPUtil formatBytes:total]];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *entries = [[SPStorage shared] scan];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.spinner stopAnimating];
            self.entries = entries;
            [self.table reloadData];
            NSArray *cells = self.table.visibleCells;
            if (cells.count) [SPAnimationKit stagger:cells offset:10];
        });
    });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"占用明细" : @"批量操作";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"「可清理」表示删掉不影响源码与工具链（例如构建中间产物）。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? (NSInteger)self.entries.count : 2;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"s"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"s"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (ip.section == 1) {
        if (ip.row == 0) {
            cell.textLabel.text = @"清理全部缓存";
            cell.textLabel.textColor = [SPTheme danger];
            cell.detailTextLabel.text = @"产物 / 日志 / 临时文件（不动源码与工具链）";
            cell.imageView.image = [UIImage systemImageNamed:@"trash.fill"];
            cell.imageView.tintColor = [SPTheme danger];
        } else {
            cell.textLabel.text = @"清理工程构建中间产物";
            cell.detailTextLabel.text = @"各工程的 .theos / packages / _build";
            cell.imageView.image = [UIImage systemImageNamed:@"hammer.fill"];
            cell.imageView.tintColor = [SPTheme warn];
        }
        return cell;
    }

    SPStorageEntry *e = self.entries[ip.row];
    cell.textLabel.text = e.title;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu 个文件%@",
                                 [SPUtil formatBytes:e.bytes], (unsigned long)e.fileCount,
                                 e.cleanableBytes ? [NSString stringWithFormat:@" · 可清理 %@",
                                                     [SPUtil formatBytes:e.cleanableBytes]] : @""];

    NSString *symbol = @"folder";
    switch (e.category) {
        case SPStorageCategoryProjects:  symbol = @"hammer.fill"; break;
        case SPStorageCategoryArtifacts: symbol = @"shippingbox.fill"; break;
        case SPStorageCategoryLogs:      symbol = @"doc.text"; break;
        case SPStorageCategoryInbox:     symbol = @"tray.and.arrow.down.fill"; break;
        case SPStorageCategoryToolchain: symbol = @"cpu.fill"; break;
        default:                         symbol = @"clock.arrow.circlepath"; break;
    }
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = [SPTheme accent];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];

    if (ip.section == 1) {
        if (ip.row == 0) [self cleanAll];
        else [self cleanProjectCaches];
        return;
    }

    SPStorageEntry *e = self.entries[ip.row];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:e.title
        message:[NSString stringWithFormat:@"占用 %@\n可清理 %@\n\n%@",
                 [SPUtil formatBytes:e.bytes],
                 [SPUtil formatBytes:e.cleanableBytes],
                 e.path]
        preferredStyle:UIAlertControllerStyleActionSheet];
    if (e.cleanableBytes > 0) {
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"清理 %@",
                                                     [SPUtil formatBytes:e.cleanableBytes]]
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            NSError *err = nil;
            unsigned long long freed = [[SPStorage shared] cleanCategory:e.category error:&err];
            [self afterClean:freed error:err];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"在文件中查看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
            initWithRootPath:e.path pickMode:NO fileFilters:nil onPick:nil];
        [self.navigationController pushViewController:b animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = tv;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cleanAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清理全部缓存"
        message:@"将删除产物、归档、日志与临时文件。工程源码与工具链不受影响。"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        unsigned long long freed = 0;
        for (NSNumber *c in @[@(SPStorageCategoryArtifacts), @(SPStorageCategoryLogs), @(SPStorageCategoryCaches)]) {
            freed += [[SPStorage shared] cleanCategory:(SPStorageCategory)c.integerValue error:NULL];
        }
        [self afterClean:freed error:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)cleanProjectCaches {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清理构建中间产物"
        message:@"会删除各工程的 .theos / packages / _build，下次编译会重新生成（耗时略长）。"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSError *err = nil;
        unsigned long long freed = [[SPStorage shared] cleanProjectCachesKeeping:nil error:&err];
        [self afterClean:freed error:err];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)afterClean:(unsigned long long)freed error:(NSError *)err {
    if (err) {
        [SPMotion hapticError];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清理未完成"
            message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [SPMotion hapticSuccess];
    [self reload];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已清理"
        message:[NSString stringWithFormat:@"释放 %@", [SPUtil formatBytes:freed]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
