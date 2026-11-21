//
//  SPProjectsViewController.m
//  项目列表 —— Apple HIG：大标题 + InsetGrouped 列表 + SF Symbols + 空状态引导
//

#import "SPProjectsViewController.h"
#import "SPNewProjectViewController.h"
#import "SPTrashViewController.h"
#import "ProjectTrash.h"
#import "SPTheme.h"
#import "SPGlassKit.h"
#import "SPTrollStoreFix.h"
#import "SPStore.h"
#import "SPProjectViewController.h"
#import "SPFileBrowserViewController.h"
#import "SPToolchain.h"
#import "SPBuilder.h"
#import "SPCompat.h"
#import "SPModels.h"
#import "SPInboxViewController.h"
#import "SPIncoming.h"
#import "SPAnimationKit.h"

NSString *const SPOpenToolchainTabNotification = @"SPOpenToolchainTab";
NSString *const SPProjectCreatedNotification = @"SPProjectCreated";

@interface SPProjectsViewController () <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, strong) UIView *emptyState;
@end

@implementation SPProjectsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPTheme background];
    self.title = @"项目";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    [self setupTable];
    [self setupSearch];
    [self setupNavItems];

    // 回收站里超过 7 天的工程自动清理（与 dylix 的 ProjectTrash 行为一致）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *trash = [self trashDirectory];
        if (![NSFileManager.defaultManager fileExistsAtPath:trash]) return;
        NSUInteger pruned = TMCPruneProjectTrash(trash, [NSDate date]);
        if (pruned) SPLog(@"[回收站] 启动清理：%lu 个过期工程", (unsigned long)pruned);
    });

    [self reloadAll];
    [self installGlassHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadAll)
                                                 name:SPProjectCreatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadAll)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSArray *cells = self.table.visibleCells;
    if (cells.count) [SPAnimationKit stagger:cells offset:12];
}

#pragma mark - 布局

- (void)setupTable {
    self.table = SPMakeInsetTable(self);
    self.table.backgroundColor = [SPTheme background];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

/// HIG：搜索放在导航栏下方，滚动时自动收起
- (void)setupSearch {
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索项目";
    self.search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}

- (void)setupNavItems {
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                        target:self action:@selector(addTapped)];
    add.accessibilityLabel = @"新建或导入项目";
    self.navigationItem.rightBarButtonItem = add;

    UIBarButtonItem *scan = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(reloadAll)];
    scan.accessibilityLabel = @"刷新项目列表";

    // 回收站入口（对齐 dylix 的 showTrash）
    UIBarButtonItem *trash = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self action:@selector(showTrash)];
    trash.accessibilityLabel = @"项目回收站";
    self.navigationItem.leftBarButtonItems = @[scan, trash];
}

#pragma mark - 数据

#pragma mark - 删除

/// 允许左滑删除。
/// 之前列表完全没有删除入口 —— 导入的项目只能去「文件」App 里手动删，
/// 而且删完 Spark 这边的 recent 记录还在，列表里会留一条打不开的空项。
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.row < (NSInteger)self.items.count;
}

- (void)tableView:(UITableView *)tv
commitEditingStyle:(UITableViewCellEditingStyle)style
forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (ip.row >= (NSInteger)self.items.count) return;

    NSDictionary *d = self.items[ip.row];
    NSString *path = d[@"path"] ?: @"";
    NSString *name = d[@"name"] ?: path.lastPathComponent;
    if (!path.length) return;

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"删除「%@」？", name]
        message:@"会同时删除磁盘上的工程目录，不可撤销。"
        preferredStyle:UIAlertControllerStyleActionSheet];

    // 与 dylix 一致：删除先移入回收站（可在 7 天内恢复），
    // 而不是立刻 removeItemAtPath —— 那是不可撤销的。
    [a addAction:[UIAlertAction actionWithTitle:@"移入回收站" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        NSError *err = nil;
        BOOL ok = [self moveProjectToTrashAtPath:path error:&err];
        [[SPStore shared] removeRecentProjectAtPath:path];
        if (!ok) {
            SPLog(@"[!] 移入回收站失败：%@", err.localizedDescription);
            [self alert:@"移入回收站失败" message:err.localizedDescription ?: @"请检查磁盘空间与权限"];
        } else {
            [SPMotion hapticSuccess];
            SPLog(@"[回收站] 已移入：%@（保留 7 天）", path.lastPathComponent);
        }
        [self reloadAll];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"彻底删除" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
        [[SPStore shared] removeRecentProjectAtPath:path];
        if (err) SPLog(@"[!] 删除工程目录失败：%@", err.localizedDescription);
        [self reloadAll];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"仅从列表移除" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
        [[SPStore shared] removeRecentProjectAtPath:path];
        [self reloadAll];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (a.popoverPresentationController) {
        UITableViewCell *c = [tv cellForRowAtIndexPath:ip];
        a.popoverPresentationController.sourceView = c ?: tv;
        a.popoverPresentationController.sourceRect = (c ?: tv).bounds;
    }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)reloadAll {
    NSMutableArray *all = [NSMutableArray arrayWithArray:[[SPStore shared] recentProjects]];

    NSString *root = [SPStore shared].projectsDirectory;
    NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    NSMutableSet *known = [NSMutableSet set];
    for (NSDictionary *d in all) [known addObject:d[@"path"]];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."]) continue;
        NSString *full = [root stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
        if (!isDir || [known containsObject:full]) continue;
        [all addObject:@{@"path": full, @"name": n, @"kind": @"", @"opened": @(0), @"summary": @""}];
    }

    // 过滤掉已不存在的路径（用户可能在文件 App 里删了）
    [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
        return [[NSFileManager defaultManager] fileExistsAtPath:d[@"path"] ?: @""];
    }]];

    if (self.filter.length) {
        [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
            return [d[@"name"] localizedCaseInsensitiveContainsString:self.filter];
        }]];
    }
    self.items = all;
    [self.table reloadData];
    [self updateEmptyState];

    // 工具链状态放在 section footer，不占列表空间。
    //
    // 以前这里无条件 rescan：每次列表刷新（含从项目返回、搜索输入）
    // 都会把整个包扫一遍，日志里会出现成片的「SDK 已找到：…」，
    // 大包扫描还会卡住主线程。改成只在「距上次扫描超过 5 秒」时才扫，
    // 并且 rescan 内部会做同样判断，双重保险。
    [[SPToolchain shared] rescanIfStale:5.0];
}

- (void)updateEmptyState {
    if (self.items.count) {
        self.table.backgroundView = nil;
        return;
    }
    if (!self.emptyState) {
        UIView *v = [[UIView alloc] init];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"hammer"]];
        icon.tintColor = [SPTheme textDim];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *title = [[UILabel alloc] init];
        title.text = @"还没有项目";
        title.font = [SPTheme scaled:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
        title.textColor = [SPTheme text];
        title.textAlignment = NSTextAlignmentCenter;
        title.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *sub = [[UILabel alloc] init];
        sub.text = @"点右上角 ＋ 新建模板，或从磁盘导入已有的 Theos 工程。";
        sub.font = [SPTheme body];
        sub.textColor = [SPTheme textDim];
        sub.numberOfLines = 0;
        sub.textAlignment = NSTextAlignmentCenter;
        sub.translatesAutoresizingMaskIntoConstraints = NO;

        for (UIView *x in @[icon, title, sub]) [v addSubview:x];
        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-90],
            [icon.widthAnchor constraintEqualToConstant:48],
            [icon.heightAnchor constraintEqualToConstant:48],

            [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
            [title.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:SPSpaceXXL],
            [title.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-SPSpaceXXL],

            [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [sub.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:SPSpaceXXL],
            [sub.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-SPSpaceXXL],
        ]];
        self.emptyState = v;
    }
    self.table.backgroundView = self.emptyState;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.filter = sc.searchBar.text ?: @"";
    [self reloadAll];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.items.count ? @"最近项目" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    // 身份问题优先提示：它会让编译必然失败，而且从编译日志里
    // 完全看不出原因（只会看到一堆 Permission denied）。
    SPTrollStoreState st = [SPTrollStoreFix state];
    if (st != SPTrollStoreStateOK) {
        // 直接给出修复路径，而不是让用户去猜。
        return (st == SPTrollStoreStateNotRoot)
            ? @"⚠️ Spark 正以非 root 运行 —— 编译会失败。\n"
               "ipa 签名是对的，问题出在安装方式：\n"
               "TrollStore 覆盖安装时没重新赋予 root 能力。\n\n"
               "修复：设置 → 工具链 → 运行身份 → 按引导重新安装"
            : @"⚠️ 签名里缺少 platform-application —— 无法提权。\n"
               "请用 TrollStore 安装官方 ipa（自签工具会替换签名）。\n\n"
               "修复：设置 → 工具链 → 运行身份";
    }

    SPToolchainScan *scan = [SPToolchain shared].scan;
    NSArray *remedies = [scan remedies];
    if (remedies.count) return [remedies componentsJoinedByString:@"\n"];
    return [NSString stringWithFormat:@"工具链：%@", [scan summary]];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *const kCell = @"project";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCell];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCell];
    [SPTheme styleCell:cell];

    NSDictionary *d = self.items[ip.row];
    NSString *kind = d[@"kind"] ?: @"";
    NSString *path = [d[@"path"] stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];

    cell.textLabel.text = d[@"name"] ?: @"";
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    // 与 dylix 一致：「类型 · N 个文件 · 最后保存 X」
    // 之前只显示「类型 · 路径」，路径又长又被截断，信息密度反而低。
    NSString *typeLabel = kind.length ? kind
        : ([d[@"name"] length] ? @"工程" : @"工程");
    NSUInteger files = [self fileCountForProjectAtPath:d[@"path"] ?: @""];
    NSString *savedText = [self savedLabelForPath:d[@"path"] ?: @""];
    if (files > 0) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu 个文件 · %@",
                                     typeLabel, (unsigned long)files, savedText];
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", typeLabel, savedText];
    }
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // HIG：用 SF Symbols 表达类型，扫一眼就知道是什么工程
    UIImage *icon = [UIImage systemImageNamed:[self symbolForKind:kind]];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
    iconView.tintColor = [SPTheme accent];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(0, 0, 28, 28);
    cell.imageView.image = icon;
    // dylix 用金色作图标强调色
    cell.imageView.tintColor = [SPTheme gold];
    (void)iconView;

    // 长按菜单（HIG 推荐 Context Menu，而不是长按弹 ActionSheet）
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSUInteger)fileCountForProjectAtPath:(NSString *)path {
    if (!path.length) return 0;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSSet *exts = [NSSet setWithArray:@[@"m", @"mm", @"x", @"xm", @"c", @"cc", @"cpp",
                                        @"h", @"hpp", @"swift", @"plist", @"mk"]];
    NSUInteger n = 0;
    for (NSString *rel in [fm enumeratorAtPath:path]) {
        if ([rel hasPrefix:@".theos"] || [rel hasPrefix:@"packages"] ||
            [rel hasPrefix:@"_build"] || [rel hasPrefix:@".git"] ||
            [rel hasPrefix:@"layout"] || [rel hasPrefix:@"obj"]) continue;
        if ([exts containsObject:rel.pathExtension.lowercaseString]) n++;
        if (n > 999) break;
    }
    return n;
}

- (NSString *)savedLabelForPath:(NSString *)path {
    NSDictionary *att = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    NSDate *date = att[NSFileModificationDate];
    if (!date) return @"尚未保存";
    NSTimeInterval ago = -[date timeIntervalSinceNow];
    if (ago < 60) return @"最后保存 刚刚";
    if (ago < 3600) return [NSString stringWithFormat:@"最后保存 %ld 分钟前", (long)(ago / 60)];
    if (ago < 86400) return [NSString stringWithFormat:@"最后保存 %ld 小时前", (long)(ago / 3600)];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"MM-dd HH:mm";
    return [NSString stringWithFormat:@"最后保存 %@", [f stringFromDate:date]];
}

- (NSString *)symbolForKind:(NSString *)kind {
    NSString *k = kind.lowercaseString;
    if ([k isEqualToString:@"tweak"]) return @"wand.and.stars";
    if ([k isEqualToString:@"app"] || [k isEqualToString:@"application"]) return @"app.badge";
    if ([k isEqualToString:@"library"]) return @"shippingbox";
    if ([k isEqualToString:@"tool"]) return @"hammer";
    if ([k isEqualToString:@"node"]) return @"curlybraces";
    return @"doc.text";
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [SPMotion hapticLight];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (cell) {
        CGPoint p = [tv.panGestureRecognizer locationInView:cell.contentView];
        [SPAnimationKit rippleIn:cell.contentView at:p color:nil];
    }
    [self openProjectAtIndexPath:ip];
}

- (void)openProjectAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *d = self.items[ip.row];
    NSError *err = nil;
    SPProject *p = [SPProject projectAtPath:d[@"path"] error:&err];
    if (!p) {
        [self presentAlert:@"打不开这个项目" message:err.localizedDescription ?: @"目录可能已被删除"];
        return;
    }
    p.options = [[SPStore shared] optionsForProjectPath:p.path];
    [[SPStore shared] pushRecentProject:p];
    SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Context Menu（HIG）

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    NSDictionary *d = self.items[ip.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIAction *remove = [UIAction actionWithTitle:@"从列表移除" image:[UIImage systemImageNamed:@"eye.slash"]
                                              identifier:nil handler:^(UIAction *a) {
            [[SPStore shared] removeRecentProjectAtPath:d[@"path"]];
            [self reloadAll];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;

        UIAction *rename = [UIAction actionWithTitle:@"重命名" image:[UIImage systemImageNamed:@"pencil"]
                                              identifier:nil handler:^(UIAction *a) {
            [self renameProjectAtIndexPath:ip];
        }];
        UIAction *share = [UIAction actionWithTitle:@"分享工程" image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                            identifier:nil handler:^(UIAction *a) {
            [self shareProjectAtIndexPath:ip];
        }];
        UIAction *copy = [UIAction actionWithTitle:@"复制路径" image:[UIImage systemImageNamed:@"doc.on.doc"]
                                           identifier:nil handler:^(UIAction *a) {
            UIPasteboard.generalPasteboard.string = d[@"path"];
            [SPMotion hapticSuccess];
        }];

        UIAction *openFolder = [UIAction actionWithTitle:@"在文件浏览中打开" image:[UIImage systemImageNamed:@"folder"]
                                                 identifier:nil handler:^(UIAction *a) {
            SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc]
                initWithRootPath:d[@"path"] pickMode:NO fileFilters:nil onPick:nil];
            [self.navigationController pushViewController:b animated:YES];
        }];
        return [UIMenu menuWithTitle:@"" children:@[openFolder, copy, remove]];
    }];
}

- (void)installGlassHeader {
    SPGlassHeaderView *header = [[SPGlassHeaderView alloc] initWithFrame:CGRectMake(0, 0, 320, 96)];
    NSUInteger n = self.items.count;
    // 对齐 dylix StudioHome 的表头：金色品牌行 + 大标题 + 一行副标题 + 两个操作按钮
    [header configureWithSymbol:@"folder.fill.badge.gearshape"
                          title:@"项目"
                       subtitle:(n ? [NSString stringWithFormat:@"%lu 个工程 · 代码、工具链都在手边", (unsigned long)n]
                                   : @"还没有工程 · 点「新建」开始")
                           tint:[SPTheme gold]];
    CGSize sz = [header systemLayoutSizeFittingSize:CGSizeMake(320, UIViewNoIntrinsicMetric)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, 320, MAX(96, sz.height));
    self.table.tableHeaderView = header;
}

#pragma mark - 新建 / 导入

- (void)addTapped {
    [SPMotion hapticLight];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"新建或导入" message:nil
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
    // 新建走独立表单页（对齐 dylix 的 StudioCreate）：
    // 模板三选一 + 名称/包标识/作者/版本/目标五个字段。
    [sheet addAction:[UIAlertAction actionWithTitle:@"新建工程…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self presentNewProjectForm];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"新建 App 工程" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptNewProjectWithTemplate:@"application"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从「文件」导入…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pickFromFilesApp];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从磁盘导入目录…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pickDirectory];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从收件箱导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        SPInboxViewController *inbox = [[SPInboxViewController alloc] init];
        [self.navigationController pushViewController:inbox animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 从「文件」App 导入

/// 从「文件」App 选一个压缩包/目录，解压到 projects 后识别成项目。
/// 为什么需要它：TrollStore 环境下用户拿到工程的方式通常是
/// 从聊天软件存到「文件」，再从这里导入 —— 之前只能从磁盘目录选，
/// 「文件」App 的位置（iCloud Drive / 我的 iPhone）根本进不去。
- (void)pickFromFilesApp {
    // 允许选任意文件（zip / tgz / deb / xz 等），也允许选目录
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"]
                                                               inMode:UIDocumentPickerModeImport];
    p.allowsMultipleSelection = NO;
    p.delegate = self;
    [self.navigationController presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c
        didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;

    // 拿安全作用域访问权限（iCloud Drive 的文件必须这么做）
    //
    // 注意：**不能**在这里 finally 里立刻 stop。
    // importFromURL: 是异步的（解压要跑子进程、可能几秒），
    // 一旦提前停止访问，后续读源文件会失败。
    // 由 importFromURL: 在自己的完成回调里负责 stop。
    BOOL access = [u startAccessingSecurityScopedResource];
    [self importFromURL:u releaseAccess:^{
        if (access) [u stopAccessingSecurityScopedResource];
    }];
}

- (void)importFromURL:(NSURL *)url releaseAccess:(void (^)(void))releaseAccess {
    NSString *name = url.lastPathComponent;
    NSString *lower = name.lowercaseString;
    NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"import-%@", NSUUID.UUID.UUIDString]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL];

    NSError *err = nil;
    NSString *src = url.path;

    // 先把源文件**复制到暂存区**再处理。
    // 这样即使外部安全作用域到期、或用户取消了文件访问，
    // 后续解压读的也是本地副本，不会出现「解压到一半读不到源文件」。
    BOOL isDir = NO;
    [fm fileExistsAtPath:src isDirectory:&isDir];
    NSString *localCopy = [staging stringByAppendingPathComponent:name];
    if (isDir) {
        if (![fm copyItemAtPath:src toPath:localCopy error:&err]) {
            if (releaseAccess) releaseAccess();
            [self alertImportFailed:err name:name];
            return;
        }
        if (releaseAccess) releaseAccess();
        [self registerImportedProjectAt:localCopy originalName:name];
        return;
    }
    if (![fm copyItemAtPath:src toPath:localCopy error:&err]) {
        if (releaseAccess) releaseAccess();
        [self alertImportFailed:err name:name];
        return;
    }
    // 源文件已复制，可以安全释放访问权限
    if (releaseAccess) releaseAccess();
    src = localCopy;

    // 2) 压缩包：解到 staging
    NSString *cmd = nil;
    if ([lower hasSuffix:@".zip"] || [lower hasSuffix:@".ipa"] || [lower hasSuffix:@".deb"]) {
        cmd = [NSString stringWithFormat:@"cd %@ && unzip -oq %@ 2>/dev/null || (dpkg-deb -x %@ %@ 2>/dev/null)",
               [SPUtil shellQuote:staging], [SPUtil shellQuote:src],
               [SPUtil shellQuote:src], [SPUtil shellQuote:staging]];
    } else if ([lower hasSuffix:@".tar.gz"] || [lower hasSuffix:@".tgz"] ||
               [lower hasSuffix:@".tar"] || [lower hasSuffix:@".tar.xz"]) {
        cmd = [NSString stringWithFormat:@"cd %@ && tar xf %@ 2>/dev/null", 
               [SPUtil shellQuote:staging], [SPUtil shellQuote:src]];
    }

    if (cmd) {
        // 必须等解压真正结束再往下找工程根，
        // 否则此时 staging 还是空的 → 永远找不到 Makefile。
        [self runUnpackCommand:cmd staging:staging originalName:name];
        return;
    } else {
        // 3) 普通单文件：直接复制过去（可能是 Tweak.x 之类，后续手动组织）
        NSString *dst = [staging stringByAppendingPathComponent:name];
        [fm copyItemAtPath:src toPath:dst error:NULL];
    }

    [self finishImportWithStaging:staging originalName:name];
}

/// 异步跑解压命令，结束后再判定工程
- (void)runUnpackCommand:(NSString *)cmd staging:(NSString *)staging originalName:(NSString *)name {
    SPSession *s = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:staging];
    __weak typeof(self) weakSelf = self;
    s.onFinish = ^(SPCommandResult *r) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 解压失败要告诉用户，而不是当成「没找到工程」塞进收件箱
        if (r.exitCode != 250 && r.exitCode != 0 && r.launchError) {
            [self alert:@"解压失败" message:r.launchError.localizedDescription];
            return;
        }
        [self finishImportWithStaging:staging originalName:name];
    };
    [s runShell:cmd];
}

/// 解压完成后：找工程根 / 落到收件箱
- (void)finishImportWithStaging:(NSString *)staging originalName:(NSString *)name {
    NSFileManager *fm = NSFileManager.defaultManager;
    // 4) 在解压结果里找工程根（含 Makefile 或 control 的目录）
    NSString *root = [self findProjectRootUnder:staging];
    if (root) {
        [self registerImportedProjectAt:root originalName:name];
    } else {
        // 没找到工程：把解压结果放进收件箱，用户可在收件箱里再处理
        NSString *inbox = [[SPStore shared] inboxDirectory];
        NSString *dst = [inbox stringByAppendingPathComponent:name.stringByDeletingPathExtension];
        [fm removeItemAtPath:dst error:NULL];
        [fm copyItemAtPath:staging toPath:dst error:NULL];
        [self alert:@"已导入到收件箱"
            message:[NSString stringWithFormat:
                     @"「%@」里没找到 Makefile/control，已放进收件箱。\n"
                     @"可以在「我的 → 收件箱」里查看或手动整理。", name]];
    }
}

/// 在目录里找工程根：优先含 Makefile，其次含 control，最多下探 3 层
- (nullable NSString *)findProjectRootUnder:(NSString *)base {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSArray *> *queue = [NSMutableArray arrayWithObject:@[base, @0]];
    NSString *fallback = nil;
    while (queue.count) {
        NSArray *item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *dir = item[0];
        NSInteger depth = [item[1] integerValue];
        if (depth > 3) continue;

        BOOL hasMakefile = [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Makefile"]];
        BOOL hasControl  = [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"control"]];
        if (hasMakefile) return dir;
        if (hasControl && !fallback) fallback = dir;

        for (NSString *sub in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[]) {
            if ([sub isEqualToString:@"__MACOSX"] || [sub hasPrefix:@"."]) continue;
            NSString *full = [dir stringByAppendingPathComponent:sub];
            BOOL d = NO;
            [fm fileExistsAtPath:full isDirectory:&d];
            if (d) [queue addObject:@[full, @(depth + 1)]];
        }
    }
    return fallback;
}

- (void)registerImportedProjectAt:(NSString *)path originalName:(NSString *)name {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *projects = [[SPStore shared] projectsDirectory];

    // 复制进 projects（保留用户原本的目录名）
    NSString *base = name.stringByDeletingPathExtension;
    if (!base.length) base = @"imported";
    NSString *dst = [projects stringByAppendingPathComponent:base];
    NSInteger n = 1;
    while ([fm fileExistsAtPath:dst]) {
        dst = [projects stringByAppendingPathComponent:
               [NSString stringWithFormat:@"%@-%ld", base, (long)++n]];
    }

    NSError *err = nil;
    if (![fm copyItemAtPath:path toPath:dst error:&err]) {
        [self alertImportFailed:err name:name];
        return;
    }

    NSError *projErr = nil;
    SPProject *p = [SPProject projectAtPath:dst error:&projErr];
    if (p) {
        p.options = [[SPStore shared] optionsForProjectPath:@"__defaults__"];
        [[SPStore shared] saveOptions:p.options forProjectPath:p.path];
        [[SPStore shared] pushRecentProject:p];

        [self reloadAll];
        [SPMotion hapticSuccess];
        [self alert:@"已导入项目"
            message:[NSString stringWithFormat:@"%@\n（%@）",
                     p.name, p.packageId.length ? p.packageId : @"未识别包名"]];
    } else {
        [self alert:@"导入失败"
            message:projErr.localizedDescription
                 ?: @"目录已复制，但没识别出工程结构。"];
    }
}

- (void)alertImportFailed:(NSError *)err name:(NSString *)name {
    [self alert:@"导入失败"
        message:[NSString stringWithFormat:@"%@\n%@", name,
                 err.localizedDescription ?: @"未知错误"]];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickDirectory {
    SPFileBrowserViewController *b = [[SPFileBrowserViewController alloc] initWithRootPath:NSHomeDirectory()
                                                                              pickMode:YES fileFilters:nil
                                                                                onPick:^(NSString *path, BOOL isDir) {
        NSError *e = nil;
        SPProject *p = [SPProject projectAtPath:path error:&e];
        if (p) {
            p.options = [[SPStore shared] optionsForProjectPath:p.path];
            [[SPStore shared] pushRecentProject:p];
        } else {
            [self alert:@"不是工程目录" message:e.localizedDescription ?: @"无法识别"];
        }
        [self reloadAll];
    }];
    [self.navigationController pushViewController:b animated:YES];
}

#pragma mark - 回收站

- (NSString *)trashDirectory {
    // projectsDirectory 形如 .../Documents/Spark/projects，
    // 回收站放同级 Spark/trash
    NSString *projects = [SPStore shared].projectsDirectory;
    return [[projects stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"trash"];
}

/// 把工程目录移入回收站并记录删除时间；顺带清理 7 天前的旧条目。
- (BOOL)moveProjectToTrashAtPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *trash = [self trashDirectory];
    if (![fm createDirectoryAtPath:trash withIntermediateDirectories:YES attributes:nil error:error])
        return NO;

    NSString *base = path.lastPathComponent ?: @"Project";
    NSString *dest = [trash stringByAppendingPathComponent:base];
    if ([fm fileExistsAtPath:dest]) {
        dest = [trash stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@-%@", base, [SPUtil timestampSlug]]];
    }

    if (![fm moveItemAtPath:path toPath:dest error:error]) return NO;

    // 与 dylix 的 ProjectTrash 同一约定：<root>/.studio-trash.json 记 deletedAt
    NSDictionary *meta = @{@"deletedAt": @([NSDate date].timeIntervalSince1970),
                           @"originalPath": path};
    NSData *data = [NSJSONSerialization dataWithJSONObject:meta options:0 error:NULL];
    if (data) {
        [data writeToFile:[dest stringByAppendingPathComponent:@".studio-trash.json"]
               atomically:YES];
    }

    NSUInteger pruned = TMCPruneProjectTrash(trash, [NSDate date]);
    if (pruned) SPLog(@"[回收站] 清理了 %lu 个过期工程", (unsigned long)pruned);
    return YES;
}

- (void)showTrash {
    SPTrashViewController *vc = [SPTrashViewController new];
    __weak typeof(self) weakSelf = self;
    vc.onChange = ^{ [weakSelf reloadAll]; };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)renameProjectAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= (NSInteger)self.items.count) return;
    NSDictionary *d = self.items[ip.row];
    NSString *oldPath = d[@"path"] ?: @"";
    NSString *oldName = d[@"name"] ?: oldPath.lastPathComponent;
    if (!oldPath.length) return;

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"重命名工程"
                                                              message:@"会同时重命名磁盘目录。"
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = oldName;
        tf.placeholder = @"新名称（英文）";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
        NSString *newName = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!newName.length || [newName isEqualToString:oldName]) return;

        NSString *dest = [[oldPath stringByDeletingLastPathComponent]
                          stringByAppendingPathComponent:newName];
        NSFileManager *fm = NSFileManager.defaultManager;
        if ([fm fileExistsAtPath:dest]) {
            [self presentAlert:@"重命名失败" message:@"同名工程已存在"];
            return;
        }
        NSError *err = nil;
        if (![fm moveItemAtPath:oldPath toPath:dest error:&err]) {
            [self presentAlert:@"重命名失败" message:err.localizedDescription ?: @"未知错误"];
            return;
        }
        [[SPStore shared] removeRecentProjectAtPath:oldPath];
        NSError *pe = nil;
        SPProject *np = [SPProject projectAtPath:dest error:&pe];
        if (np) [[SPStore shared] pushRecentProject:np];
        [SPMotion hapticSuccess];
        [self reloadAll];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)shareProjectAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= (NSInteger)self.items.count) return;
    NSString *path = self.items[ip.row][@"path"];
    if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) return;

    NSString *name = path.lastPathComponent;
    NSString *zip = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"%@.zip", name]];
    [NSFileManager.defaultManager removeItemAtPath:zip error:NULL];

    NSString *cmd = [NSString stringWithFormat:@"cd %@ && zip -qry %@ %@",
                     [SPUtil shellQuote:path.stringByDeletingLastPathComponent],
                     [SPUtil shellQuote:zip], [SPUtil shellQuote:name]];
    SPSession *sess = [[SPSession alloc] initWithEnvironment:@{} workingDirectory:NSTemporaryDirectory()];
    sess.timeout = 120;
    __weak typeof(self) weakSelf = self;
    sess.onFinish = ^(SPCommandResult *r) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (r.exitCode != 0 || ![NSFileManager.defaultManager fileExistsAtPath:zip]) {
                [weakSelf presentAlert:@"打包失败" message:r.stderrText ?: @"zip 命令不可用"];
                return;
            }
            UIActivityViewController *av = [[UIActivityViewController alloc]
                initWithActivityItems:@[[NSURL fileURLWithPath:zip]] applicationActivities:nil];
            if (av.popoverPresentationController) {
                UITableViewCell *c = [weakSelf.table cellForRowAtIndexPath:ip];
                av.popoverPresentationController.sourceView = c ?: weakSelf.view;
                av.popoverPresentationController.sourceRect = (c ?: weakSelf.view).bounds;
            }
            [weakSelf presentViewController:av animated:YES completion:nil];
        });
    };
    [sess runShell:cmd];
}

- (void)presentNewProjectForm {
    SPNewProjectViewController *vc = [SPNewProjectViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    __weak typeof(self) weakSelf = self;
    vc.onFinish = ^(NSString *createdPath) {
        if (!createdPath.length) return;
        [weakSelf openCreatedProjectAtPath:createdPath];
    };
    [self presentViewController:nav animated:YES completion:nil];
}

/// 表单创建成功后：套用默认构建选项、入最近列表、直接打开工程页
- (void)openCreatedProjectAtPath:(NSString *)path {
    NSError *e = nil;
    SPProject *p = [SPProject projectAtPath:path error:&e];
    if (!p) {
        [self alert:@"创建失败" message:e.localizedDescription ?: @"模板生成异常"];
        return;
    }
    p.options = [[SPStore shared] optionsForProjectPath:@"__defaults__"];
    [[SPStore shared] saveOptions:p.options forProjectPath:p.path];
    [[SPStore shared] pushRecentProject:p];
    [self reloadAll];
    SPProjectViewController *detail = [[SPProjectViewController alloc] initWithProject:p];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)promptNewProjectWithTemplate:(NSString *)tpl {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建工程"
        message:( [tpl isEqualToString:@"tweak"] ? @"一个最小可编译的 tweak（hook SpringBoard）" : @"一个最小可运行的空 App")
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"工程名（英文，如 MyTweak）";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"包标识";
        tf.text = @"com.example.";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *name = a.textFields[0].text;
        NSString *bundle = a.textFields[1].text;
        if (!name.length) return;
        NSError *err = nil;
        NSString *path = [self createProjectTemplate:tpl name:name bundleId:bundle error:&err];
        if (!path) {
            [self presentAlert:@"创建失败" message:err.localizedDescription ?: @"同名工程可能已存在"];
            return;
        }
        [SPMotion hapticSuccess];
        NSError *e = nil;
        SPProject *p = [SPProject projectAtPath:path error:&e];
        if (!p) {
            [self alert:@"创建失败" message:e.localizedDescription ?: @"模板生成异常"];
            return;
        }
        // 新建项目套用「设置 → 编译默认值 + 混淆」
        p.options = [[SPStore shared] optionsForProjectPath:@"__defaults__"];
        [[SPStore shared] saveOptions:p.options forProjectPath:p.path];
        [[SPStore shared] pushRecentProject:p];
        [self reloadAll];
        SPProjectViewController *vc = [[SPProjectViewController alloc] initWithProject:p];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSString *)createProjectTemplate:(NSString *)tpl name:(NSString *)name bundleId:(NSString *)bundleId error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [SPStore shared].projectsDirectory;
    NSString *path = [root stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:path]) {
        if (error) *error = SPError(SPErrorCodeIO, @"同名工程已存在");
        return nil;
    }
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    BOOL isApp = [tpl isEqualToString:@"application"];
    NSString *identifier = bundleId.length && ![bundleId isEqualToString:@"com.example."]
        ? bundleId : [@"com.example." stringByAppendingString:name.lowercaseString];

    NSString *makefile = isApp
        ? [NSString stringWithFormat:@"TARGET = iphone:clang:latest:15.0\n"
                                     "ARCHS = arm64 arm64e\n\n"
                                     "include $(THEOS)/makefiles/common.mk\n\n"
                                     "APPLICATION_NAME = %@\n\n"
                                     "%@_FILES = main.m RootViewController.m\n"
                                     "%@_FRAMEWORKS = UIKit Foundation\n\n"
                                     "include $(THEOS_MAKE_PATH)/application.mk\n", name, name, name, name]
        : [NSString stringWithFormat:@"TARGET = iphone:clang:latest:15.0\n"
                                     "ARCHS = arm64 arm64e\n"
                                     "INSTALL_TARGET_PROCESSES = SpringBoard\n\n"
                                     "include $(THEOS)/makefiles/common.mk\n\n"
                                     "TWEAK_NAME = %@\n\n"
                                     "%@_FILES = Tweak.x\n"
                                     "%@_CFLAGS = -fobjc-arc\n\n"
                                     "include $(THEOS_MAKE_PATH)/tweak.mk\n", name, name, name];
    [makefile writeToFile:[path stringByAppendingPathComponent:@"Makefile"] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL];

    NSString *control = [NSString stringWithFormat:
        @"Package: %@\nName: %@\nVersion: 1.0.0\nArchitecture: iphoneos-arm\n"
         "Description: 由 Spark 创建\nMaintainer: Spark\nAuthor: Spark\nSection: %@\n",
        identifier, name, isApp ? @"Applications" : @"Tweaks"];
    [control writeToFile:[path stringByAppendingPathComponent:@"control"] atomically:YES
                encoding:NSUTF8StringEncoding error:NULL];

    if (isApp) {
        [@"#import <UIKit/UIKit.h>\n#import \"RootViewController.h\"\n\n"
          "@interface AppDelegate : UIResponder <UIApplicationDelegate>\n"
          "@property (nonatomic, strong) UIWindow *window;\n@end\n\n"
          "@implementation AppDelegate\n"
          "- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {\n"
          "    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];\n"
          "    self.window.rootViewController = [RootViewController new];\n"
          "    [self.window makeKeyAndVisible];\n    return YES;\n}\n@end\n\n"
          "int main(int argc, char *argv[]) {\n    @autoreleasepool {\n"
          "        return UIApplicationMain(argc, argv, nil, @\"AppDelegate\");\n    }\n}\n"
         writeToFile:[path stringByAppendingPathComponent:@"main.m"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
        [@"#import <UIKit/UIKit.h>\n\n@interface RootViewController : UIViewController\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"RootViewController.h"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
        [@"#import \"RootViewController.h\"\n\n@implementation RootViewController\n\n"
          "- (void)viewDidLoad {\n    [super viewDidLoad];\n"
          "    self.title = @\"Hello\";\n"
          "    self.view.backgroundColor = [UIColor systemBackgroundColor];\n\n"
          "    UILabel *label = [[UILabel alloc] init];\n"
          "    label.text = @\"Hello Spark\";\n"
          "    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];\n"
          "    label.translatesAutoresizingMaskIntoConstraints = NO;\n"
          "    [self.view addSubview:label];\n"
          "    [NSLayoutConstraint activateConstraints:@[\n"
          "        [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],\n"
          "        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],\n"
          "    ]];\n}\n\n@end\n"
         writeToFile:[path stringByAppendingPathComponent:@"RootViewController.m"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
    } else {
        [@"// Spark 生成的 tweak：最简单的 SpringBoard hook\n%hook SpringBoard\n\n"
          "- (void)applicationDidFinishLaunching:(id)application {\n"
          "    %orig;\n    NSLog(@\"[%@] loaded\");\n}\n\n%end\n"
         writeToFile:[path stringByAppendingPathComponent:@"Tweak.x"] atomically:YES
         encoding:NSUTF8StringEncoding error:NULL];
    }

    [fm createDirectoryAtPath:[path stringByAppendingPathComponent:@"layout/DEBIAN"]
  withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"*.deb\npackages/\n.theos/\n_build/\n*.dSYM/\nobj/\n.sparkbak/\n"
     writeToFile:[path stringByAppendingPathComponent:@".gitignore"] atomically:YES
        encoding:NSUTF8StringEncoding error:NULL];
    return path;
}

#pragma mark - 工具

- (void)presentAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
