//
//  SPSignatureViewController.m
//

#import "SPSignatureViewController.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPCompat.h"
#import "SPSignatureAudit.h"
#import "SPStore.h"
#import <sys/wait.h>
#import <spawn.h>
#import <crt_externs.h>

@interface SPSignatureViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<SPAuditIssue *> *issues;
@property (nonatomic, copy, nullable) NSString *target;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
/// 状态文案：渲染在分区 footer 里（不占头部空间）
@property (nonatomic, copy, nullable) NSString *statusText;
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

    self.table = SPMakeInsetTable(self);
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    // 统一玻璃头部：与其它页面保持一致的顶部观感
    self.table.tableHeaderView = SPTableHeader(@"checkmark.shield.fill", @"签名审计", @"排查 ipa 装不上的原因", [SPTheme accent], 320);

    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // 状态文案走 statusText 属性，渲染在分区 footer 里
    self.statusText = @"选一个 ipa（或已解包的 Payload 目录）检查装不上的原因";

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

/// 状态统一放这里，由 tableView 的 footer 渲染。
/// 之前是自己拼了一个 frame 写死的 UILabel 当 tableHeaderView，
/// 既不响应动态字体，还会覆盖掉统一的玻璃头部。
- (void)updateSummaryText:(NSString *)text color:(UIColor *)color {
    // UIKit 的 footer 只吃纯文本，color 目前只用于将来扩展；
    // 保留参数是为了调用处语义清晰（成功/失败）。
    self.statusText = text;
    [self.table reloadData];
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
    [self updateSummaryText:@"正在审计…" color:[SPTheme textDim]];

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
            posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)argv, *_NSGetEnviron());
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
                [self updateSummaryText:@"✅ 未发现问题\n该包应当可以正常安装" color:[SPTheme success]];
            } else {
                NSUInteger err = 0;
                for (SPAuditIssue *i in result) if (i.level == SPAuditLevelError) err++;
                [self updateSummaryText:[NSString stringWithFormat:
                    @"发现 %lu 项错误、%lu 项警告\n点每项看详情与建议",
                    (unsigned long)err, (unsigned long)(result.count - err)]
                                  color:err ? [SPTheme danger] : [SPTheme warn]];
            }
        });
    });
}

#pragma mark - 表格

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return self.statusText;
}

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
