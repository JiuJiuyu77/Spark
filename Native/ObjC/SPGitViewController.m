//
//  SPGitViewController.m
//

#import "SPGitViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPGit.h"
#import "SPDiffViewController.h"
#import "SPEditorViewController.h"
#import "SPCompat.h"

typedef NS_ENUM(NSInteger, SPGitSection) {
    SPGitSectionBranch = 0,
    SPGitSectionChanges,
    SPGitSectionActions,
    SPGitSectionCount,
};

@interface SPGitViewController ()
@property (nonatomic, copy) NSString *root;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSDictionary *status;
@property (nonatomic, strong) NSArray<SPGitFileStatus *> *files;
@property (nonatomic, strong) NSArray<SPGitCommit *> *history;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation SPGitViewController

- (instancetype)initWithProjectRoot:(NSString *)root {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _root = [root copy];
        _files = @[];
        _history = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"Git";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.headerLabel = [[UILabel alloc] init];
    self.headerLabel.font = [SPTheme mono:11];
    self.headerLabel.textColor = [SPTheme textDim];
    self.headerLabel.textAlignment = NSTextAlignmentCenter;
    self.headerLabel.numberOfLines = 2;
    self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerLabel];

    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"g"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"arrow.triangle.branch", @"版本管理", @"查看改动、提交、推送", [SPTheme accent], 320);

    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [self.headerLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SPSpaceL],
        [self.headerLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SPSpaceL],
        [self.table.topAnchor constraintEqualToAnchor:self.headerLabel.bottomAnchor constant:4],
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
    __weak typeof(self) weakSelf = self;
    dispatch_async([SPGit queue], ^{
        NSError *err = nil;
        NSDictionary *st = [[SPGit shared] statusAtRoot:weakSelf.root error:&err];
        NSArray *hist = [[SPGit shared] historyRoot:weakSelf.root limit:20];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            [self.spinner stopAnimating];
            self.status = st;
            self.files = st[@"files"] ?: @[];
            self.history = hist ?: @[];
            self.headerLabel.text = st
                ? [NSString stringWithFormat:@"分支 %@  ·  %lu 个改动",
                   st[@"branch"] ?: @"?", (unsigned long)self.files.count]
                : @"尚未初始化 git 仓库";
            [self.table reloadData];
        });
    });
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SPGitSectionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SPGitSectionBranch:  return @"仓库";
        case SPGitSectionChanges: return self.files.count ? @"改动" : nil;
        default:                  return @"操作";
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == SPGitSectionChanges) return @"左滑单个文件可暂存/取消暂存；点开看 diff。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case SPGitSectionBranch:  return self.status ? 2 : 1;   // 分支 / 历史条数
        case SPGitSectionChanges: return (NSInteger)self.files.count;
        default:                  return 5;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"g"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"g"];
    [SPTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [SPTheme text];

    if (ip.section == SPGitSectionBranch) {
        if (!self.status) {
            cell.textLabel.text = @"初始化 git 仓库";
            cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
            cell.imageView.tintColor = [SPTheme accent];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        }
        if (ip.row == 0) {
            cell.textLabel.text = @"当前分支";
            cell.detailTextLabel.text = self.status[@"branch"];
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.triangle.branch"];
            cell.imageView.tintColor = [SPTheme accent];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"提交历史";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 条", (unsigned long)self.history.count];
            cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
            cell.imageView.tintColor = [SPTheme info];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }

    if (ip.section == SPGitSectionChanges) {
        SPGitFileStatus *f = self.files[ip.row];
        cell.textLabel.text = f.path.lastPathComponent;
        cell.textLabel.font = [SPTheme mono:13];
        cell.detailTextLabel.text = f.path.stringByDeletingLastPathComponent;
        cell.detailTextLabel.numberOfLines = 1;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingHead;

        NSString *symbol = @"circle";
        UIColor *tint = [SPTheme textDim];
        if (f.untracked) { symbol = @"questionmark.circle.fill"; tint = [SPTheme warn]; }
        else if ([f.status isEqualToString:@"M"]) { symbol = @"pencil.circle.fill"; tint = [SPTheme accent]; }
        else if ([f.status isEqualToString:@"A"]) { symbol = @"plus.circle.fill"; tint = [SPTheme success]; }
        else if ([f.status isEqualToString:@"D"]) { symbol = @"minus.circle.fill"; tint = [SPTheme danger]; }
        else if ([f.status isEqualToString:@"R"]) { symbol = @"arrow.right.circle.fill"; tint = [SPTheme info]; }
        cell.imageView.image = [UIImage systemImageNamed:symbol];
        cell.imageView.tintColor = tint;

        // 已暂存的用勾标区分
        cell.accessoryType = f.staged ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.tintColor = [SPTheme success];
        return cell;
    }

    NSArray *titles = @[@"暂存全部改动", @"提交…", @"查看全部 diff", @"设置远端…", @"推送"];
    NSArray *symbols = @[@"tray.and.arrow.down.fill", @"checkmark.circle.fill",
                         @"doc.text.magnifyingglass", @"link", @"arrow.up.circle.fill"];
    cell.textLabel.text = titles[ip.row];
    cell.imageView.image = [UIImage systemImageNamed:symbols[ip.row]];
    cell.imageView.tintColor = ip.row == 4 ? [SPTheme success] : [SPTheme accent];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    BOOL hasChanges = self.files.count > 0;
    if ((ip.row == 0 || ip.row == 1) && !hasChanges) cell.textLabel.textColor = [SPTheme textDim];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];

    if (ip.section == SPGitSectionBranch) {
        if (!self.status) { [self doInit]; return; }
        if (ip.row == 1) [self showHistory];
        return;
    }

    if (ip.section == SPGitSectionChanges) {
        [self showDiffForFile:self.files[ip.row]];
        return;
    }

    switch (ip.row) {
        case 0: [self doStageAll]; break;
        case 1: [self doCommit]; break;
        case 2: [self showDiffForFile:nil]; break;
        case 3: [self doSetRemote]; break;
        default: [self doPush]; break;
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != SPGitSectionChanges) return nil;
    SPGitFileStatus *f = self.files[ip.row];
    NSString *title = f.staged ? @"取消暂存" : @"暂存";
    UIContextualAction *act = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                      title:title
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        NSError *err = nil;
        BOOL ok = f.staged
            ? [[SPGit shared] unstagePaths:@[f.path] root:self.root error:&err]
            : [[SPGit shared] stagePaths:@[f.path] root:self.root error:&err];
        if (!ok) [self alert:@"操作失败" message:err.localizedDescription];
        done(ok);
        [self reload];
    }];
    act.backgroundColor = f.staged ? [SPTheme warn] : [SPTheme success];
    return [UISwipeActionsConfiguration configurationWithActions:@[act]];
}

#pragma mark - 操作

- (void)doInit {
    __weak typeof(self) weakSelf = self;
    dispatch_async([SPGit queue], ^{
        NSError *err = nil;
        BOOL ok = [[SPGit shared] initializeRoot:weakSelf.root error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            if (!ok) [self alert:@"初始化失败" message:err.localizedDescription];
            else { [SPMotion hapticSuccess]; [self reload]; }
        });
    });
}

- (void)doStageAll {
    __weak typeof(self) weakSelf = self;
    dispatch_async([SPGit queue], ^{
        NSError *err = nil;
        BOOL ok = [[SPGit shared] stagePaths:@[] root:weakSelf.root error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            if (!ok) [self alert:@"暂存失败" message:err.localizedDescription];
            else { [SPMotion hapticSuccess]; [self reload]; }
        });
    });
}

- (void)doCommit {
    if (!self.files.count) { [self alert:@"没有改动" message:@"先修改文件再提交。"]; return; }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *lastName = [d stringForKey:@"Spark.gitName"] ?: @"Spark";
    NSString *lastEmail = [d stringForKey:@"Spark.gitEmail"] ?: @"spark@localhost";

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"提交"
        message:[NSString stringWithFormat:@"将提交 %lu 个改动", (unsigned long)self.files.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"提交信息";
        tf.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"提交" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *msg = a.textFields[0].text;
        if (!msg.length) return;
        [d setObject:lastName forKey:@"Spark.gitName"];
        [d setObject:lastEmail forKey:@"Spark.gitEmail"];
        __weak typeof(self) weakSelf = self;
        dispatch_async([SPGit queue], ^{
            NSError *err = nil;
            // 先全部暂存，再提交（最省事的流程）
            [[SPGit shared] stagePaths:@[] root:weakSelf.root error:NULL];
            NSString *hash = [[SPGit shared] commitRoot:weakSelf.root message:msg
                                                   name:lastName email:lastEmail error:&err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf; if (!self) return;
                if (!hash) [self alert:@"提交失败" message:err.localizedDescription];
                else {
                    [SPMotion hapticSuccess];
                    [self toast:[NSString stringWithFormat:@"已提交 %@", hash]];
                    [self reload];
                }
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showDiffForFile:(nullable SPGitFileStatus *)file {
    __weak typeof(self) weakSelf = self;
    dispatch_async([SPGit queue], ^{
        NSString *diff = [[SPGit shared] diffRoot:weakSelf.root path:file.path staged:file.staged];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            NSString *name = file ? file.path.lastPathComponent : @"全部改动";

            if (!diff.length) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"没有差异"
                    message:@"该文件与暂存区/HEAD 一致。" preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
                return;
            }

            // 用行级着色视图而不是裸文本编辑器：
            // 加号绿底、减号红底、@@ 蓝色，一眼看出改了哪几行
            SPDiffViewController *vc = [[SPDiffViewController alloc] initWithDiff:diff title:name];
            [self.navigationController pushViewController:vc animated:YES];
        });
    });
}

- (void)showHistory {
    NSMutableString *text = [NSMutableString string];
    for (SPGitCommit *c in self.history) {
        [text appendFormat:@"%@  %@\n  %@ · %@\n\n", c.shortHash, c.message, c.author, c.date];
    }
    if (!text.length) text = [NSMutableString stringWithString:@"还没有提交"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"提交历史"
        message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)doSetRemote {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"设置远端"
        message:@"格式 owner/repo（会用 https://github.com/... 拼接）" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"JiuJiuyu77/MyTweak";
        tf.text = [d stringForKey:@"Spark.gitRemote"] ?: @"";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *repo = a.textFields[0].text;
        if (!repo.length) return;
        [d setObject:repo forKey:@"Spark.gitRemote"];
        NSString *url = [repo hasPrefix:@"http"] ? repo : [@"https://github.com/" stringByAppendingString:repo];
        if (![url hasSuffix:@".git"]) url = [url stringByAppendingString:@".git"];
        __weak typeof(self) weakSelf = self;
        dispatch_async([SPGit queue], ^{
            NSError *err = nil;
            BOOL ok = [[SPGit shared] setRemoteRoot:weakSelf.root url:url error:&err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf; if (!self) return;
                if (!ok) [self alert:@"设置失败" message:err.localizedDescription];
                else [self toast:@"远端已设置"];
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)doPush {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *remote = [d stringForKey:@"Spark.gitRemote"];
    if (!remote.length) { [self alert:@"还没设置远端" message:@"先点「设置远端…」填 owner/repo。"]; return; }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"推送"
        message:@"GitHub token（只用于本次推送，不写入仓库配置）" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"ghp_...";
        tf.secureTextEntry = YES;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"推送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *token = a.textFields[0].text;
        if (!token.length) return;
        NSString *branch = [[SPGit shared] currentBranchRoot:self.root] ?: @"main";
        if ([branch isEqualToString:@"(空仓库)"]) branch = @"main";
        __weak typeof(self) weakSelf = self;
        [self.spinner startAnimating];
        dispatch_async([SPGit queue], ^{
            NSError *err = nil;
            NSString *out = [[SPGit shared] pushRoot:weakSelf.root remote:@"origin" branch:branch
                                               token:token error:&err];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf; if (!self) return;
                [self.spinner stopAnimating];
                if (!err) {
                    [SPMotion hapticSuccess];
                    [self alert:@"推送完成" message:out ?: @"已推送到远端"];
                } else {
                    [self alert:@"推送失败" message:err.localizedDescription];
                }
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 工具

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

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
