//
//  SPInboxViewController.m
//

#import "SPInboxViewController.h"
#import "SPTheme.h"
#import "SPIncoming.h"
#import "SPStore.h"
#import "SPCompat.h"
#import "SPProjectViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchain.h"

@interface SPInboxViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPIncomingItem *> *items;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation SPInboxViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"收件箱";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"i"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importTapped)];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    // 每次进页面先把 Share Extension 留下的搬进来
    NSArray *drained = [[SPIncoming shared] drainSharedIncoming];
    if (drained.count) {
        [SPMotion hapticSuccess];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self toast:[NSString stringWithFormat:@"收到 %lu 个文件", (unsigned long)drained.count]];
        });
    }
    self.items = [[SPIncoming shared] items];
    [self.table reloadData];
    [self updateEmpty];
}

- (void)updateEmpty {
    if (self.items.count) { self.table.backgroundView = nil; return; }
    if (!self.emptyLabel) {
        UILabel *l = [[UILabel alloc] init];
        l.text = @"收件箱是空的\n\n在别的 App 里点「分享 → 存入 Spark」，\n或点右上角 ＋ 从「文件」导入。";
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
    if (!self.items.count) return nil;
    return [NSString stringWithFormat:@"%lu 项 · %@", (unsigned long)self.items.count,
            [SPUtil formatBytes:[[SPIncoming shared] totalSize]]];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (!self.items.count) return nil;
    return @"点「工程」类可直接注册成项目；插件类会出现在注入器的插件列表里。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"i"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"i"];
    [SPTheme styleCell:cell];
    SPIncomingItem *it = self.items[ip.row];

    cell.textLabel.text = it.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", it.kindText, [SPUtil formatBytes:it.size]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    NSString *symbol = @"doc";
    UIColor *tint = [SPTheme textDim];
    switch (it.kind) {
        case SPIncomingKindProject: symbol = @"hammer.fill"; tint = [SPTheme accent]; break;
        case SPIncomingKindPlugin:  symbol = @"shippingbox.fill"; tint = [SPTheme info]; break;
        case SPIncomingKindPackage: symbol = @"archivebox.fill"; tint = [SPTheme warn]; break;
        case SPIncomingKindSDK:     symbol = @"cpu.fill"; tint = [SPTheme success]; break;
        default: break;
    }
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = tint;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPIncomingItem *it = self.items[ip.row];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:it.name
        message:[NSString stringWithFormat:@"%@ · %@", it.kindText, [SPUtil formatBytes:it.size]]
        preferredStyle:UIAlertControllerStyleActionSheet];

    if (it.kind == SPIncomingKindProject || it.kind == SPIncomingKindPackage) {
        [a addAction:[UIAlertAction actionWithTitle:@"导入为项目" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self importAsProject:it];
        }]];
    }
    if (it.kind == SPIncomingKindPlugin || it.kind == SPIncomingKindPackage) {
        [a addAction:[UIAlertAction actionWithTitle:@"去注入器使用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self.navigationController popToRootViewControllerAnimated:NO];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SPOpenToolsTab" object:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SPOpenInjector" object:it.path];
        }]];
    }
    if (it.kind == SPIncomingKindSDK) {
        [a addAction:[UIAlertAction actionWithTitle:@"装到工具链 SDK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self toast:@"已放入 SDK 目录，去工具链页选它"];
            [[SPToolchain shared] rescan];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"在文件中查看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
            initWithRootPath:[it.path stringByDeletingLastPathComponent] pickMode:NO fileFilters:nil onPick:nil];
        [self.navigationController pushViewController:b animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[SPIncoming shared] remove:it];
        [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = tv;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)importAsProject:(SPIncomingItem *)it {
    NSError *err = nil;
    NSString *path = [[SPIncoming shared] makeProjectFrom:it error:&err];
    if (!path) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入失败"
            message:err.localizedDescription ?: @"无法识别为工程" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        [SPMotion hapticError];
        return;
    }
    SPProject *p = [SPProject projectAtPath:path error:NULL];
    if (p) {
        p.options = [[SPStore shared] optionsForProjectPath:@"__defaults__"];
        [[SPStore shared] optionsForProjectPath:p.path];
        [[SPStore shared] saveOptions:p.options forProjectPath:p.path];
        [[SPStore shared] pushRecentProject:p];
    }
    [SPMotion hapticSuccess];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已导入为项目"
        message:path.lastPathComponent preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"去看看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 导入

- (void)importTapped {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.data", @"public.item", @"public.folder"]
                       inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    p.allowsMultipleSelection = YES;
    [self.navigationController presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSInteger ok = 0;
    for (NSURL *u in urls) {
        NSError *err = nil;
        if ([[SPIncoming shared] importPath:u.path error:&err]) ok++;
    }
    if (ok) [SPMotion hapticSuccess];
    [self reload];
}

#pragma mark - Toast

- (void)toast:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightMedium];
    l.textColor = [SPTheme text];
    l.backgroundColor = [SPTheme surface];
    l.textAlignment = NSTextAlignmentCenter;
    [SPTheme round:l radius:SPRadiusM];
    l.clipsToBounds = YES;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [l.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-SPSpaceHuge],
        [l.heightAnchor constraintEqualToConstant:32],
        [l.widthAnchor constraintGreaterThanOrEqualToConstant:160],
    ]];
    [SPMotion appear:^{ l.alpha = 1; }];
    [SPMotion disappear:^{ l.alpha = 0; } completion:^{ [l removeFromSuperview]; }];
}

@end
