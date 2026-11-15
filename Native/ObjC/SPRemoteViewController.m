//
//  SPRemoteViewController.m
//

#import "SPRemoteViewController.h"
#import "SPTheme.h"
#import "SPRemoteServer.h"
#import "SPCompat.h"

@interface SPRemoteViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *bigCode;
@property (nonatomic, strong) UILabel *bigURL;
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SPRemoteViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"局域网工作台";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self buildHeader];
    [self buildTable];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshHeader];
    [self.table reloadData];
}

#pragma mark - 头部（大字地址 + 访问码）

- (void)buildHeader {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [SPTheme surface];
    [SPTheme round:card radius:16];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    self.bigCode = [[UILabel alloc] init];
    self.bigCode.font = [SPTheme mono:40 weight:UIFontWeightBold];
    self.bigCode.textColor = [SPTheme accent];
    self.bigCode.textAlignment = NSTextAlignmentCenter;
    self.bigCode.text = @"------";
    self.bigCode.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bigCode];

    self.bigURL = [[UILabel alloc] init];
    self.bigURL.font = [SPTheme mono:12];
    self.bigURL.textColor = [SPTheme textDim];
    self.bigURL.textAlignment = NSTextAlignmentCenter;
    self.bigURL.numberOfLines = 2;
    self.bigURL.text = @"未启动";
    self.bigURL.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.bigURL];

    UILabel *tip = [[UILabel alloc] init];
    tip.text = @"电脑浏览器打开上面的地址，输入这 6 位码";
    tip.font = [SPTheme caption];
    tip.textColor = [SPTheme textDim];
    tip.textAlignment = NSTextAlignmentCenter;
    tip.numberOfLines = 2;
    tip.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:tip];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.bigCode.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [self.bigCode.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.bigCode.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [self.bigURL.topAnchor constraintEqualToAnchor:self.bigCode.bottomAnchor constant:6],
        [self.bigURL.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.bigURL.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [tip.topAnchor constraintEqualToAnchor:self.bigURL.bottomAnchor constant:10],
        [tip.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [tip.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [tip.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];
    self.headerCard = card;
}

- (void)refreshHeader {
    SPRemoteServer *s = [SPRemoteServer shared];
    if (s.isRunning) {
        self.bigCode.text = s.accessCode ?: @"------";
        self.bigURL.text = s.baseURL ?: @"（无局域网地址）";
        self.bigURL.textColor = [SPTheme info];
    } else {
        self.bigCode.text = @"------";
        self.bigURL.text = @"未启动";
        self.bigURL.textColor = [SPTheme textDim];
    }
}

- (void)buildTable {
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"r"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:4],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"服务" : @"说明";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"只监听局域网，默认关闭；HTTP 明文，仅限可信网络使用。";
    return @"网页支持：浏览文件、编辑保存（自动备份 .sparkbak）、触发构建、看构建历史。\n"
            "写入限制在 Spark 的 projects 目录内，不能越界。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 4 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"r"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"r"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textColor = [SPTheme text];
    SPRemoteServer *s = [SPRemoteServer shared];

    if (ip.section == 1) {
        cell.textLabel.text = @"把手机当成编译服务器";
        cell.detailTextLabel.text = @"同一 WiFi";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    switch (ip.row) {
        case 0: {
            cell.textLabel.text = @"启用服务";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = s.isRunning;
            [sw addTarget:self action:@selector(toggleServer:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case 1:
            cell.textLabel.text = @"端口";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)(s.port ?: 8787)];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case 2:
            cell.textLabel.text = @"更换访问码";
            cell.detailTextLabel.text = s.isRunning ? @"点击刷新" : @"启动后可用";
            cell.textLabel.textColor = s.isRunning ? [SPTheme accent] : [SPTheme textDim];
            break;
        default:
            cell.textLabel.text = @"复制访问地址";
            cell.detailTextLabel.text = s.isRunning ? @"含访问码" : @"未启动";
            cell.textLabel.textColor = s.isRunning ? [SPTheme accent] : [SPTheme textDim];
            break;
    }
    return cell;
}

- (void)toggleServer:(UISwitch *)sw {
    SPRemoteServer *s = [SPRemoteServer shared];
    if (sw.isOn) {
        NSInteger port = [[NSUserDefaults standardUserDefaults] integerForKey:@"Spark.remotePort"];
        if (port <= 0) port = 8787;
        NSError *err = nil;
        if (![s startWithPort:port error:&err]) {
            sw.on = NO;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"启动失败"
                message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
            [SPMotion hapticError];
            return;
        }
        [SPMotion hapticSuccess];
    } else {
        [s stop];
    }
    [self refreshHeader];
    [self.table reloadData];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    SPRemoteServer *s = [SPRemoteServer shared];

    if (ip.section == 1) {
        [self showHelp];
        return;
    }
    switch (ip.row) {
        case 1: {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"端口"
                message:@"改端口前请先关闭服务" preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSNumber *p in @[@8787, @8080, @9000, @17878]) {
                [a addAction:[UIAlertAction actionWithTitle:[p stringValue] style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *x) {
                    [[NSUserDefaults standardUserDefaults] setInteger:p.integerValue forKey:@"Spark.remotePort"];
                    [self.table reloadData];
                }]];
            }
            [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            a.popoverPresentationController.sourceView = tv;
            [self presentViewController:a animated:YES completion:nil];
            break;
        }
        case 2:
            if (!s.isRunning) { [self toast:@"先启用服务"]; return; }
            [s rotateAccessCode];
            [self refreshHeader];
            [SPMotion hapticSuccess];
            [self toast:@"已更换访问码"];
            break;
        default: {
            if (!s.isRunning) { [self toast:@"先启用服务"]; return; }
            NSString *text = [NSString stringWithFormat:@"%@/?code=%@", s.baseURL ?: @"", s.accessCode ?: @""];
            UIPasteboard.generalPasteboard.string = text;
            [SPMotion hapticSuccess];
            [self toast:@"已复制"];
            break;
        }
    }
}

- (void)showHelp {
    NSString *msg =
        @"1. 打开「启用服务」\n"
         "2. 电脑与手机连同一个 WiFi\n"
         "3. 电脑浏览器打开 http://手机IP:8787\n"
         "4. 输入手机上显示的 6 位访问码\n\n"
         "能做什么：\n"
         "· 浏览项目文件，直接编辑保存（自动留 .sparkbak 备份）\n"
         "· 点「构建」在手机上编译\n"
         "· 看构建历史\n\n"
         "限制：\n"
         "· 明文 HTTP，不要在公共网络上开\n"
         "· 只能访问 Spark 的 projects 目录\n"
         "· iOS 后台会挂起服务，切回前台恢复";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"使用说明"
        message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)toast:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightMedium];
    l.textColor = [SPTheme text];
    l.backgroundColor = [SPTheme surface];
    l.textAlignment = NSTextAlignmentCenter;
    [SPTheme round:l radius:10];
    l.clipsToBounds = YES;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [l.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-28],
        [l.heightAnchor constraintEqualToConstant:32],
        [l.widthAnchor constraintGreaterThanOrEqualToConstant:160],
    ]];
    [SPMotion appear:^{ l.alpha = 1; }];
    [SPMotion disappear:^{ l.alpha = 0; } completion:^{ [l removeFromSuperview]; }];
}

@end
