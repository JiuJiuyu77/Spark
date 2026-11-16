//
//  SPSignatureViewController.m
//

#import "SPSignatureViewController.h"
#import "SPTheme.h"
#import "SPCompat.h"
#import "SPSignatureAudit.h"
#import "SPStore.h"
#import <sys/wait.h>

@interface SPSignatureViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<SPAuditIssue *> *issues;
@property (nonatomic, copy, nullable) NSString *target;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *summaryLabel;
@end

@implementation SPSignatureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = @"签名审计";
    self.view.backgroundColor = [SPTheme background];
    self.issues = [NSMutableArray array];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(pickFile)];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.textAlignment = NSTextAlignmentCenter;
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    self.summaryLabel.textColor = [SPTheme textDim];
    self.table.tableHeaderView = [self makeHeader];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (UIView *)makeHeader {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    self.summaryLabel.frame = CGRectMake(20, 12, 280, 72);
    [v addSubview:self.summaryLabel];
    self.summaryLabel.text = @"选一个 ipa（或已解包的 Payload 目录）\n检查装不上的原因：缺签名 / 文件截断 / 空壳 bundle / ar 静态库";
    return v;
}

- (void)pickFile {
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"]
                                                               inMode:UIDocumentPickerModeImport];
    p.delegate = self;
    [self.navigationController presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    [self auditPath:u.path];
}

- (void)auditPath:(NSString *)path {
    [self.spinner startAnimating];
    self.summaryLabel.text = @"正在审计…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *appPath = path;
        NSFileManager *fm = NSFileManager.defaultManager;

        // 若是 ipa，先解到临时目录
        if ([[path lowercaseString] hasSuffix:@".ipa"]) {
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"spark-audit"];
            [fm removeItemAtPath:tmp error:NULL];
            [fm createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:NULL];
            // 用系统 unzip（TrollStore 环境有）
            pid_t pid = 0;
            NSString *cmd = [NSString stringWithFormat:@"unzip -oq %@ -d %@",
                             [SPUtil shellQuote:path], [SPUtil shellQuote:tmp]];
            const char *argv[] = {"/bin/sh", "-c", cmd.UTF8String, NULL};
            posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)argv, environ);
            int st = 0; waitpid(pid, &st, 0);
            appPath = [tmp stringByAppendingPathComponent:@"Payload"];
        }

        NSArray<SPAuditIssue *> *result = [SPSignatureAudit auditPayloadAtPath:appPath];
        if (!result) result = [SPSignatureAudit auditAppAtPath:appPath];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.target = path.lastPathComponent;
            [self.issues setArray:result];
            [self.table reloadData];

            if (!result.count) {
                self.summaryLabel.textColor = [SPTheme success];
                self.summaryLabel.text = @"✅ 未发现问题\n该包应当可以正常安装";
            } else {
                NSUInteger err = 0;
                for (SPAuditIssue *i in result) if (i.level == SPAuditLevelError) err++;
                self.summaryLabel.textColor = err ? [SPTheme danger] : [SPTheme warn];
                self.summaryLabel.text = [NSString stringWithFormat:
                    @"发现 %lu 项错误、%lu 项警告\n点每项看详情与建议",
                    (unsigned long)err, (unsigned long)(result.count - err)];
            }
        });
    });
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.issues.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];

    SPAuditIssue *i = self.issues[ip.row];
    cell.textLabel.text = i.summary;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = i.relativePath;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSString *symbol = i.level == SPAuditLevelError ? @"xmark.octagon.fill"
                    : i.level == SPAuditLevelWarn  ? @"exclamationmark.triangle.fill"
                                                   : @"checkmark.circle.fill";
    UIColor *tint = i.level == SPAuditLevelError ? [SPTheme danger]
                  : i.level == SPAuditLevelWarn  ? [SPTheme warn]
                                                 : [SPTheme success];
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = tint;
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SPAuditIssue *i = self.issues[ip.row];
    NSMutableString *m = [NSMutableString string];
    if (i.relativePath.length) [m appendFormat:@"文件：%@\n\n", i.relativePath];
    if (i.detail.length)       [m appendFormat:@"详情：%@\n\n", i.detail];
    if (i.suggestion.length)   [m appendFormat:@"建议：%@", i.suggestion];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:i.summary
        message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
