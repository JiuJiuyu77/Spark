//
//  RBFileBrowserViewController.m
//

#import "RBFileBrowserViewController.h"
#import "RBTheme.h"
#import "RBEditorViewController.h"
#import "RBCompat.h"

@interface RBFileRow : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) unsigned long long size;
@end
@implementation RBFileRow
@end

@interface RBFileBrowserViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSString *current;
@property (nonatomic, assign) BOOL pickMode;
@property (nonatomic, copy, nullable) NSArray<NSString *> *filters;
@property (nonatomic, copy, nullable) RBFilePickHandler onPick;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<RBFileRow *> *rows;
@property (nonatomic, strong) UILabel *pathLabel;
@end

@implementation RBFileBrowserViewController

- (instancetype)initWithRootPath:(NSString *)rootPath
                        pickMode:(BOOL)pickMode
                     fileFilters:(NSArray<NSString *> *)extensions
                          onPick:(RBFilePickHandler)onPick {
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
    self.view.backgroundColor = [RBTheme background];
    self.title = self.current.lastPathComponent;

    self.pathLabel = [[UILabel alloc] init];
    self.pathLabel.font = [RBTheme monoFont:10];
    self.pathLabel.textColor = [RBTheme textDim];
    self.pathLabel.numberOfLines = 2;
    self.pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pathLabel];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.backgroundColor = [RBTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorColor = [RBTheme separator];
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    [NSLayoutConstraint activateConstraints:@[
        [self.pathLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.pathLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.pathLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.table.topAnchor constraintEqualToAnchor:self.pathLabel.bottomAnchor constant:8],
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
        RBFileRow *r = [RBFileRow new];
        r.name = n; r.fullPath = full; r.isDirectory = isDir;
        r.size = [fm attributesOfItemAtPath:full error:NULL].fileSize;
        [isDir ? dirs : files addObject:r];
    }
    NSArray *cmp = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]];
    self.rows = [[dirs sortedArrayUsingDescriptors:cmp] arrayByAddingObjectsFromArray:[files sortedArrayUsingDescriptors:cmp]];
    NSString *shown = [self.current stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
    self.pathLabel.text = shown;
    [self.table reloadData];
    self.title = self.current.lastPathComponent;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"row" forIndexPath:ip];
    RBFileRow *r = self.rows[ip.row];
    cell.backgroundColor = [RBTheme background];
    cell.textLabel.font = [RBTheme monoFont:13];

    NSString *icon = r.isDirectory ? @"▸" : [self iconForFile:r.name];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", icon, r.name];
    cell.textLabel.textColor = r.isDirectory ? [RBTheme info] : [RBTheme text];
    return cell;
}

- (NSString *)iconForFile:(NSString *)name {
    NSString *ext = name.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"deb"]) return @"❏";
    if ([ext isEqualToString:@"x"] || [ext isEqualToString:@"xm"]) return @"ⓧ";
    if ([ext isEqualToString:@"m"] || [ext isEqualToString:@"mm"]) return @"ⓜ";
    if ([ext isEqualToString:@"h"]) return @"Ⓗ";
    if ([ext isEqualToString:@"plist"]) return @"Ⓟ";
    if ([ext isEqualToString:@"json"]) return @"{}";
    if ([name isEqualToString:@"Makefile"]) return @"Ⓜ";
    return @"·";
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    RBFileRow *r = self.rows[ip.row];
    if (r.isDirectory) {
        RBFileBrowserViewController *next = [[RBFileBrowserViewController alloc] initWithRootPath:r.fullPath
                                                                                       pickMode:self.pickMode
                                                                                    fileFilters:self.filters
                                                                                         onPick:self.onPick];
        next.onOpenFile = self.onOpenFile;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }
    if (self.pickMode) {
        if (self.onPick) self.onPick(r.fullPath, NO);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if (self.onOpenFile) self.onOpenFile(r.fullPath);
    if (![NSFileManager.defaultManager isReadableFileAtPath:r.fullPath]) return;
    RBEditorViewController *editor = [[RBEditorViewController alloc] initWithFilePath:r.fullPath];
    [self.navigationController pushViewController:editor animated:YES];
}

@end
