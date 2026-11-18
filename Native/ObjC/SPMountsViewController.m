//
//  SPMountsViewController.m
//

#import "SPMountsViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPMount.h"
#import "SPCompat.h"
#import "SPFileBrowserViewController.h"

@interface SPMountsViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPMount *> *items;
@end

@implementation SPMountsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"外部文件夹";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"externaldrive.fill", @"外部文件夹", @"挂载 NAS / WebDAV，像本地目录一样用", [SPTheme accent], 320);

    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                        target:self action:@selector(addTapped)];
    self.navigationItem.rightBarButtonItem = add;

    [self reload];
}

- (void)reload {
    [[SPMountManager shared] reload];
    self.items = [[SPMountManager shared] mounts];
    [self.table reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 1) return @"文件 App";
    return self.items.count ? @"已挂载的远端目录" : @"还没有挂载";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        return @"开启后，每个挂载点会在「文件」App 的「我的 iPhone → Spark」下出现一个快捷方式（挂载-xxx）。\n"
                "点进去就是本地镜像目录；配合「同步到本地」可以离线查看与编译。";
    }
    if (self.items.count) {
        return @"挂载会出现在「文件」里 Mounts 目录下，能直接当项目目录用。\n凭据保存在钥匙串，不写进配置文件。";
    }
    return @"将 NAS / Mac 共享 / WebDAV 服务器的目录挂到 Spark 里，\n就能像本地文件夹一样浏览、编译、取产物。\n\n点右上角 ＋ 添加。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 1 ? 1 : self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];

    if (ip.section == 1) {
        cell.textLabel.text = @"在「文件」App 中显示挂载";
        cell.detailTextLabel.text = @"我的 iPhone → Spark → 挂载-xxx";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [SPMountManager shared].exposeToFilesApp;
        [sw addTarget:self action:@selector(toggleExpose:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    [SPTheme styleCell:cell];
    SPMount *m = self.items[ip.row];
    cell.textLabel.text = m.displayName;
    cell.imageView.image = [UIImage systemImageNamed:(m.kind == SPMountKindWebDAV ? @"externaldrive.connected.to.line.below"
                                                                                : @"network")];
    cell.imageView.tintColor = [SPTheme accent];
    NSString *target = m.kind == SPMountKindWebDAV
        ? (m.baseURL ?: @"")
        : [NSString stringWithFormat:@"smb://%@@%@/%@" , m.username ?: @"", m.smbHost ?: @"", m.share ?: @""];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@%@", [m kindString], target,
                                 m.readOnly ? @" · 只读" : @""];
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)toast:(NSString *)text {
    if (!text.length) return;
    UIAlertController *hud = [UIAlertController alertControllerWithTitle:nil
        message:text preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:hud animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [hud dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)toggleExpose:(UISwitch *)sw {
    [SPMountManager shared].exposeToFilesApp = sw.isOn;
    [SPMotion hapticLight];
    [self toast:sw.isOn ? @"已在文件 App 中显示" : @"已从文件 App 中隐藏"];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) return;
    [SPMotion hapticLight];
    SPMount *m = self.items[ip.row];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:m.displayName message:[m kindString]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"浏览" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self browse:m path:@"/"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"测试连接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self test:m];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"同步到本地（文件 App 可见）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self syncLocal:m];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"在本地查看挂载点" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
            initWithRootPath:m.localRootPath pickMode:NO fileFilters:nil onPick:nil];
        [self.navigationController pushViewController:b animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"移除挂载" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[SPMountManager shared] removeMount:m];
        [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = tv;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)browse:(SPMount *)m path:(NSString *)path {
    SPMountBrowser *b = [[SPMountBrowser alloc] initWithMount:m path:path];
    [self.navigationController pushViewController:b animated:YES];
}

- (void)syncLocal:(SPMount *)m {
    UIAlertController *hud = [UIAlertController alertControllerWithTitle:@"正在同步"
        message:@"首次同步会拉取目录结构与文件…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:hud animated:YES completion:nil];

    [[SPMountManager shared] syncMount:m progress:^(NSString *status) {
        hud.message = status;
    } completion:^(BOOL ok, NSError *err) {
        [hud dismissViewControllerAnimated:YES completion:^{
            if (ok) {
                [self toast:@"同步完成，文件 App 里可见"];
            } else {
                UIAlertController *e = [UIAlertController alertControllerWithTitle:@"同步失败"
                    message:err.localizedDescription ?: @"未知错误" preferredStyle:UIAlertControllerStyleAlert];
                [e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:e animated:YES completion:nil];
            }
        }];
    }];
}

- (void)test:(SPMount *)m {
    __weak typeof(self) weakSelf = self;
    [[SPMountManager shared] testMount:m completion:^(BOOL ok, NSString *detail) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"连接正常" : @"连接失败"
            message:detail preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        if (ok) [SPMotion hapticSuccess]; else [SPMotion hapticError];
    }];
}

#pragma mark - 添加

- (void)addTapped {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加外部文件夹" message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"WebDAV" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self promptAdd:SPMountKindWebDAV];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"SMB（NAS / Mac 共享）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self promptAdd:SPMountKindSMB];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptAdd:(SPMountKind)kind {
    BOOL isDAV = kind == SPMountKindWebDAV;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:(isDAV ? @"添加 WebDAV" : @"添加 SMB")
        message:(isDAV ? @"服务器地址示例：https://nas.local:5006/dav" : @"共享示例：192.168.1.10/share" )
        preferredStyle:UIAlertControllerStyleAlert];

    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"显示名称（如 群晖）";
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = isDAV ? @"https://host:port/path" : @"host 或 host/share";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.keyboardType = UIKeyboardTypeURL;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"用户名（可留空）";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"密码";
        tf.secureTextEntry = YES;
    }];

    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *name = a.textFields[0].text;
        NSString *addr = a.textFields[1].text;
        NSString *user = a.textFields[2].text;
        NSString *pass = a.textFields[3].text;
        if (!addr.length) return;

        SPMount *m = [SPMount new];
        m.displayName = name.length ? name : addr.lastPathComponent;
        m.kind = kind;
        m.username = user;
        if (isDAV) {
            m.baseURL = addr;
        } else {
            // host/share 或 host
            NSArray *parts = [addr componentsSeparatedByString:@"/"];
            m.smbHost = parts.firstObject;
            m.share = parts.count > 1 ? parts[1] : @"";
            m.smbPort = 445;
        }
        [[SPMountManager shared] addMount:m password:pass];
        [self reload];
        [self test:m];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - 远端浏览页

@interface SPMountBrowser ()
@property (nonatomic, strong) SPMount *mount;
@property (nonatomic, copy) NSString *remotePath;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPMountEntry *> *entries;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SPMountBrowser

- (instancetype)initWithMount:(SPMount *)mount path:(NSString *)path {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _mount = mount;
        _remotePath = [path copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = [self.remotePath isEqualToString:@"/"] ? self.mount.displayName : self.remotePath.lastPathComponent;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"e"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [SPTheme accent];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    [self load];
}

- (void)load {
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[SPMountManager shared] listPath:self.remotePath ofMount:self.mount completion:^(NSArray<SPMountEntry *> *entries, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        [self.spinner stopAnimating];
        if (error) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"读取失败"
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
            return;
        }
        self.entries = entries;
        [self.table reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.entries.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"e"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"e"];
    [SPTheme styleCell:cell];
    SPMountEntry *e = self.entries[ip.row];
    cell.textLabel.text = e.name;
    cell.imageView.image = [UIImage systemImageNamed:(e.isDirectory ? @"folder.fill" : @"doc")];
    cell.imageView.tintColor = e.isDirectory ? [SPTheme accent] : [SPTheme textDim];
    cell.detailTextLabel.text = e.isDirectory ? @"" : [SPUtil formatBytes:e.size];
    cell.accessoryType = e.isDirectory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) return;
    SPMountEntry *e = self.entries[ip.row];
    if (e.isDirectory) {
        NSString *next = e.path;
        if (![next hasSuffix:@"/"]) next = [next stringByAppendingString:@"/"];
        SPMountBrowser *b = [[SPMountBrowser alloc] initWithMount:self.mount path:next];
        [self.navigationController pushViewController:b animated:YES];
    } else {
        [self downloadEntry:e];
    }
}

/// 下载到本地挂载点，然后用内置编辑器/分享打开
- (void)downloadEntry:(SPMountEntry *)e {
    NSString *localName = e.name;
    NSString *local = [self.mount.localRootPath stringByAppendingPathComponent:localName];
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[SPMountManager shared] download:e.path ofMount:self.mount toLocal:local completion:^(BOOL ok, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        [self.spinner stopAnimating];
        if (!ok) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"下载失败"
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
            return;
        }
        [SPMotion hapticSuccess];
        SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
            initWithRootPath:[local stringByDeletingLastPathComponent] pickMode:NO fileFilters:nil onPick:nil];
        [self.navigationController pushViewController:b animated:YES];
    }];
}

@end
