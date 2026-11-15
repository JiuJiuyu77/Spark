//
//  SPMeViewController.m
//

#import "SPMeViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPSettingsViewController.h"
#import "SPLogsViewController.h"
#import "SPMountsViewController.h"
#import "SPInboxViewController.h"
#import "SPIncoming.h"
#import "SPToolchain.h"
#import "SPToolchainInstaller.h"
#import "SPStore.h"
#import "SPCompat.h"
#import "SPMount.h"
#import "SPFileBrowserViewController.h"

@interface SPMeViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSArray *> *groups;
@property (nonatomic, strong) NSArray<NSString *> *titles;
@end

@implementation SPMeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"我的";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"m"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self buildGroups];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildGroups];
    [self.table reloadData];
}

- (void)buildGroups {
    self.titles = @[@"", @"通用", @"关于"];
    self.groups = @[
        @[@"设置"],
        @[@"收件箱", @"日志", @"外部文件夹", @"数据目录"],
        @[@"版本信息", @"运行环境自检"],
    ];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)self.groups.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.titles[s].length ? self.titles[s] : nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)self.groups[s].count;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 0 ? 64 : 48;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"m"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"m"];
    [SPTheme styleCell:cell];

    NSString *title = self.groups[ip.section][ip.row];
    cell.textLabel.text = title;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.detailTextLabel.text = nil;

    if (ip.section == 0) {
        cell.textLabel.font = [SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
        cell.imageView.image = [self tile:@"gearshape.fill" tint:[SPTheme accent]];
    } else if (ip.section == 1) {
        if ([title isEqualToString:@"收件箱"]) {
            NSUInteger n = [[SPIncoming shared] items].count;
            cell.detailTextLabel.text = n ? [NSString stringWithFormat:@"%lu 个文件", (unsigned long)n] : @"空";
            cell.imageView.image = [self tile:@"tray.and.arrow.down.fill" tint:[SPTheme accent]];
        } else if ([title isEqualToString:@"日志"]) {
            NSUInteger n = [NSFileManager.defaultManager contentsOfDirectoryAtPath:[[SPStore shared] logsDirectory]
                                                                            error:NULL].count;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条", (unsigned long)n];
            cell.imageView.image = [self tile:@"doc.text.magnifyingglass" tint:[SPTheme info]];
        } else if ([title isEqualToString:@"外部文件夹"]) {
            NSUInteger n = [[SPMountManager shared] mounts].count;
            cell.detailTextLabel.text = n ? [NSString stringWithFormat:@"%lu 个", (unsigned long)n] : @"未挂载";
            cell.imageView.image = [self tile:@"externaldrive.connected.to.line.below" tint:[SPTheme success]];
        } else {
            cell.imageView.image = [self tile:@"folder.fill" tint:[SPTheme warn]];
        }
    } else {
        if ([title isEqualToString:@"版本信息"]) {
            cell.detailTextLabel.text = SPVersion.shared.semver;
            cell.imageView.image = [self tile:@"info.circle.fill" tint:[SPTheme textDim]];
        } else {
            cell.imageView.image = [self tile:@"stethoscope" tint:[SPTheme textDim]];
        }
    }
    return cell;
}

- (UIImage *)tile:(NSString *)symbol tint:(UIColor *)tint {
    CGSize size = CGSizeMake(29, 29);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, 29) cornerRadius:7];
        [tint colorWithAlphaComponent:0.16].setFill;
        [p fill];
        UIImage *sym = [UIImage systemImageNamed:symbol
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                               weight:UIImageSymbolWeightSemibold]];
        UIImage *tinted = [sym imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize s = tinted.size;
        [tinted drawInRect:CGRectMake((29 - s.width) / 2, (29 - s.height) / 2, s.width, s.height)];
    }];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    NSString *title = self.groups[ip.section][ip.row];
    UIViewController *vc = nil;

    if ([title isEqualToString:@"设置"]) vc = [SPSettingsViewController new];
    else if ([title isEqualToString:@"收件箱"]) vc = [SPInboxViewController new];
    else if ([title isEqualToString:@"日志"]) vc = [SPLogsViewController new];
    else if ([title isEqualToString:@"外部文件夹"]) vc = [SPMountsViewController new];
    else if ([title isEqualToString:@"数据目录"]) {
        SPToolchainScan *scan = [SPToolchain shared].scan;
        NSMutableString *msg = [NSMutableString string];
        [msg appendFormat:@"文档目录\n%@\n\n工具链\n%@\n", NSHomeDirectory(), [scan summary]];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"数据目录" message:msg
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    } else if ([title isEqualToString:@"版本信息"]) {
        NSString *msg = [NSString stringWithFormat:@"Spark %@\n构建 %@\n%@\n\nMIT License",
                         SPVersion.shared.semver, SPVersion.shared.gitDescribe, SPVersion.shared.builtAt];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Spark" message:msg
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    } else {
        NSString *msg = [NSString stringWithFormat:@"内置工具链：%@\n已展开：%@\n\n%@",
                         [SPToolchainInstaller shared].hasBundledToolchain ? @"有" : @"无",
                         [SPToolchainInstaller shared].isInstalled ? @"是" : @"否",
                         [[SPToolchain shared].scan summary]];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"环境自检" message:msg
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

@end
