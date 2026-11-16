//
//  SPFileBrowserViewController.m
//  文件浏览 —— HIG：InsetGrouped 列表 + SF Symbols 文件类型图标 + 面包屑路径
//

#import "SPFileBrowserViewController.h"
#import "SPTheme.h"
#import "SPEditorViewController.h"
#import "SPCompat.h"
#import "SPMount.h"
#import "SPMountsViewController.h"

@interface SPFileRow : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, copy, nullable) NSString *mountDescriptor;
@end
@implementation SPFileRow
@end

@interface SPFileBrowserViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSString *current;
@property (nonatomic, assign) BOOL pickMode;
@property (nonatomic, copy, nullable) NSArray<NSString *> *filters;
@property (nonatomic, copy, nullable) SPFilePickHandler onPick;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<SPFileRow *> *rows;
@property (nonatomic, strong) UILabel *pathLabel;
@end

@implementation SPFileBrowserViewController

- (instancetype)initWithRootPath:(NSString *)rootPath
                        pickMode:(BOOL)pickMode
                     fileFilters:(NSArray<NSString *> *)extensions
                          onPick:(SPFilePickHandler)onPick {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _root = [rootPath copy];
        _current = [rootPath copy];
        _pickMode = pickMode;
        _filters = [extensions copy];
        _onPick = [onPick copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = self.current.lastPathComponent;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.pathLabel = [[UILabel alloc] init];
    self.pathLabel.font = [SPTheme mono:10];
    self.pathLabel.textColor = [SPTheme textDim];
    self.pathLabel.numberOfLines = 2;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    self.pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pathLabel];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [SPTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.pathLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.pathLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:SPSpaceL],
        [self.pathLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-SPSpaceL],
        [self.table.topAnchor constraintEqualToAnchor:self.pathLabel.bottomAnchor constant:4],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self reload];
}

- (void)reload {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *names = [fm contentsOfDirectoryAtPath:self.current error:NULL] ?: @[];
    NSMutableArray *dirs = [NSMutableArray array], *files = [NSMutableArray array];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."] && ![n isEqualToString:@".theos"]) continue;
        NSString *full = [self.current stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        [fm fileExistsAtPath:full isDirectory:&isDir];
        if (!isDir && self.filters.count) {
            BOOL match = NO;
            for (NSString *ext in self.filters) {
                if ([n.pathExtension.lowercaseString isEqualToString:ext.lowercaseString]) { match = YES; break; }
            }
            if (!match) continue;
        }
        SPFileRow *r = [SPFileRow new];
        r.name = n;
        r.fullPath = full;
        r.isDirectory = isDir;
        r.size = [fm attributesOfItemAtPath:full error:NULL].fileSize;

        // 目录里有 .sparkmount 就当作挂载点（点进去走远端浏览）
        if (isDir) {
            NSString *desc = [full stringByAppendingPathComponent:@".sparkmount"];
            if ([fm fileExistsAtPath:desc]) r.mountDescriptor = desc;
        }
        [isDir ? dirs : files addObject:r];
    }
    NSArray *cmp = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]];
    self.rows = [[dirs sortedArrayUsingDescriptors:cmp] arrayByAddingObjectsFromArray:[files sortedArrayUsingDescriptors:cmp]];
    self.pathLabel.text = [self.current stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
    [self.table reloadData];
    self.title = self.current.lastPathComponent.length ? self.current.lastPathComponent : @"文件";
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"row" forIndexPath:ip];
    SPFileRow *r = self.rows[ip.row];
    [SPTheme styleCell:cell];

    // HIG：文件类型用 SF Symbols 表达，不用自绘字符
    cell.textLabel.text = r.name;
    cell.textLabel.font = [SPTheme mono:13];
    cell.imageView.image = [UIImage systemImageNamed:[self symbolForRow:r]];
    cell.imageView.tintColor = r.isDirectory ? [SPTheme accent] : [SPTheme textDim];
    cell.accessoryType = r.isDirectory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = r.isDirectory ? nil : [SPUtil formatBytes:r.size];
    return cell;
}

- (NSString *)symbolForRow:(SPFileRow *)r {
    if (r.mountDescriptor) return @"externaldrive.connected.to.line.below";
    if (r.isDirectory) return @"folder.fill";
    NSString *ext = r.name.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"deb"]) return @"shippingbox.fill";
    if ([ext isEqualToString:@"x"] || [ext isEqualToString:@"xm"]) return @"wand.and.stars";
    if ([ext isEqualToString:@"m"] || [ext isEqualToString:@"mm"] || [ext isEqualToString:@"c"]) return @"chevron.left.forwardslash.chevron.right";
    if ([ext isEqualToString:@"h"]) return @"doc.plaintext";
    if ([ext isEqualToString:@"plist"]) return @"list.bullet.rectangle";
    if ([ext isEqualToString:@"json"]) return @"curlybraces";
    if ([ext isEqualToString:@"dylib"]) return @"shippingbox";
    if ([r.name isEqualToString:@"Makefile"]) return @"hammer";
    return @"doc";
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SPFileRow *r = self.rows[ip.row];

    if (r.mountDescriptor) {
        NSData *d = [NSData dataWithContentsOfFile:r.mountDescriptor];
        NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        SPMount *m = [SPMount mountFromDictionary:j ?: @{}];
        SPMountBrowser *b = [[SPMountBrowser alloc] initWithMount:m path:@"/"];
        [self.navigationController pushViewController:b animated:YES];
        return;
    }
    if (r.isDirectory) {
        SPFileBrowserViewController *next = [[SPFileBrowserViewController alloc]
            initWithRootPath:r.fullPath pickMode:self.pickMode fileFilters:self.filters onPick:self.onPick];
        next.onOpenFile = self.onOpenFile;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    [SPMotion hapticLight];
    if (self.pickMode) {
        if (self.onPick) self.onPick(r.fullPath, NO);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.onOpenFile) self.onOpenFile(r.fullPath);
    if (![NSFileManager.defaultManager isReadableFileAtPath:r.fullPath]) return;
    SPEditorViewController *editor = [[SPEditorViewController alloc] initWithFilePath:r.fullPath];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - Context Menu

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    SPFileRow *r = self.rows[ip.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIAction *copy = [UIAction actionWithTitle:@"复制路径" image:[UIImage systemImageNamed:@"doc.on.doc"]
                                           identifier:nil handler:^(UIAction *a) {
            UIPasteboard.generalPasteboard.string = r.fullPath;
            [SPMotion hapticSuccess];
        }];
        UIAction *share = [UIAction actionWithTitle:@"分享文件" image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                            identifier:nil handler:^(UIAction *a) {
            UIActivityViewController *av = [[UIActivityViewController alloc]
                initWithActivityItems:@[[NSURL fileURLWithPath:r.fullPath]] applicationActivities:nil];
            av.popoverPresentationController.sourceView = tv;
            av.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
            [self presentViewController:av animated:YES completion:nil];
        }];
        NSMutableArray *items = [NSMutableArray arrayWithObject:copy];
        if (!r.isDirectory) [items insertObject:share atIndex:0];
        return [UIMenu menuWithTitle:r.name children:items];
    }];
}

@end
