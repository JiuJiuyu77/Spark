//
//  SPTrashViewController.m
//  Spark —— 项目回收站
//
#import "SPTrashViewController.h"
#import "SPStore.h"
#import "SPTheme.h"
#import "SPMotion.h"
#import "SPCompat.h"
#import "ProjectTrash.h"

@interface SPTrashViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;   // @{name, path, deletedAt, originalPath}
@end

@implementation SPTrashViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"回收站";
    self.tableView.backgroundColor = [SPTheme background];
    self.tableView.rowHeight = 64;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(emptyTapped)];

    [self reloadEntries];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadEntries];
}

#pragma mark - 数据

- (NSString *)trashDirectory {
    NSString *projects = [SPStore shared].projectsDirectory;
    return [[projects stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"trash"];
}

- (void)reloadEntries {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *trash = [self trashDirectory];
    NSMutableArray *out = [NSMutableArray array];

    for (NSString *name in [fm contentsOfDirectoryAtPath:trash error:NULL] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *root = [trash stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;

        NSDictionary *meta = nil;
        NSData *data = [NSData dataWithContentsOfFile:
                        [root stringByAppendingPathComponent:@".studio-trash.json"]];
        if (data) meta = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];

        NSNumber *deletedAt = [meta isKindOfClass:NSDictionary.class] ? meta[@"deletedAt"] : nil;
        NSString *original = [meta isKindOfClass:NSDictionary.class] ? meta[@"originalPath"] : nil;

        [out addObject:@{
            @"name": name,
            @"path": root,
            @"deletedAt": deletedAt ?: @0,
            @"originalPath": original ?: @"",
        }];
    }

    // 最近删除的排前面
    self.entries = [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"deletedAt"] compare:a[@"deletedAt"]];
    }];
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.entries.count) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *l = [[UILabel alloc] init];
    l.text = @"回收站是空的\n\n删除的工程会在这里保留 7 天，可随时恢复。";
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    l.textColor = [SPTheme textDim];
    self.tableView.backgroundView = l;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"trash"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"trash"];
    cell.backgroundColor = [SPTheme surface];
    cell.textLabel.textColor = [SPTheme text];
    cell.detailTextLabel.textColor = [SPTheme textDim];
    cell.imageView.image = [UIImage systemImageNamed:@"trash"];
    cell.imageView.tintColor = [SPTheme danger];

    NSDictionary *e = self.entries[ip.row];
    cell.textLabel.text = e[@"name"];

    NSNumber *ts = e[@"deletedAt"];
    if ([ts doubleValue] > 0) {
        NSDate *when = [NSDate dateWithTimeIntervalSince1970:[ts doubleValue]];
        NSTimeInterval age = -[when timeIntervalSinceNow];
        NSInteger daysLeft = MAX(0, 7 - (NSInteger)(age / 86400.0));
        NSDateFormatter *f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"MM-dd HH:mm";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"删除于 %@ · 还剩 %ld 天",
                                     [f stringFromDate:when], (long)daysLeft];
    } else {
        cell.detailTextLabel.text = @"删除时间未知";
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.row < (NSInteger)self.entries.count;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
 trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= (NSInteger)self.entries.count) return nil;
    NSDictionary *e = self.entries[ip.row];

    UIContextualAction *restore = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                          title:@"恢复"
                                                                        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        BOOL ok = [self restoreEntry:e];
        done(ok);
    }];
    restore.backgroundColor = [SPTheme success];
    restore.image = [UIImage systemImageNamed:@"arrow.uturn.backward"];

    UIContextualAction *kill = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                       title:@"彻底删除"
                                                                     handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSError *err = nil;
        BOOL ok = [NSFileManager.defaultManager removeItemAtPath:e[@"path"] error:&err];
        if (!ok) SPLog(@"[回收站] 删除失败：%@", err.localizedDescription);
        [self reloadEntries];
        if (self.onChange) self.onChange();
        done(ok);
    }];
    kill.image = [UIImage systemImageNamed:@"trash.slash"];

    return [UISwipeActionsConfiguration configurationWithActions:@[kill, restore]];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row >= (NSInteger)self.entries.count) return;
    NSDictionary *e = self.entries[ip.row];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"「%@」", e[@"name"]]
        message:@"可以恢复到原来的项目目录。"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) { [self restoreEntry:e]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"彻底删除" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        NSError *err = nil;
        [NSFileManager.defaultManager removeItemAtPath:e[@"path"] error:&err];
        [self reloadEntries];
        if (self.onChange) self.onChange();
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (a.popoverPresentationController) {
        UITableViewCell *c = [tv cellForRowAtIndexPath:ip];
        a.popoverPresentationController.sourceView = c ?: tv;
        a.popoverPresentationController.sourceRect = (c ?: tv).bounds;
    }
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 动作

- (BOOL)restoreEntry:(NSDictionary *)e {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *path = e[@"path"];
    NSString *original = e[@"originalPath"];
    NSString *projects = [SPStore shared].projectsDirectory;

    // 原路径不可用（比如工程目录已被占用）时，恢复到 projects 下同名目录
    NSString *dest = original.length ? original
        : [projects stringByAppendingPathComponent:e[@"name"]];
    if ([fm fileExistsAtPath:dest]) {
        dest = [projects stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@-%@", e[@"name"], [SPUtil timestampSlug]]];
    }
    [fm createDirectoryAtPath:[dest stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES attributes:nil error:NULL];

    NSError *err = nil;
    BOOL ok = [fm moveItemAtPath:path toPath:dest error:&err];
    if (!ok) {
        SPLog(@"[回收站] 恢复失败：%@", err.localizedDescription);
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"恢复失败"
                                                                  message:err.localizedDescription ?: @"未知错误"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return NO;
    }

    // 移除回收标记
    [fm removeItemAtPath:[dest stringByAppendingPathComponent:@".studio-trash.json"] error:NULL];
    [SPMotion hapticSuccess];
    SPLog(@"[回收站] 已恢复：%@", dest.lastPathComponent);

    [self reloadEntries];
    if (self.onChange) self.onChange();
    return YES;
}

- (void)emptyTapped {
    if (!self.entries.count) return;
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"清空回收站？"
        message:[NSString stringWithFormat:@"将彻底删除 %lu 个工程，不可恢复。",
                 (unsigned long)self.entries.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        NSFileManager *fm = NSFileManager.defaultManager;
        for (NSDictionary *e in self.entries) {
            [fm removeItemAtPath:e[@"path"] error:NULL];
        }
        [self reloadEntries];
        if (self.onChange) self.onChange();
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end