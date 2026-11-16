//
//  SPHelpViewController.m
//

#import "SPHelpViewController.h"
#import "SPTheme.h"
#import "SPCompat.h"
#import "SPHelp.h"
#import "SPAnimationKit.h"

@interface SPHelpArticleViewController : UIViewController
@property (nonatomic, strong) SPHelpArticle *article;
@end

@implementation SPHelpArticleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = self.article.title;
    self.view.backgroundColor = [SPTheme background];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.selectable = YES;
    tv.backgroundColor = UIColor.clearColor;
    tv.textContainerInset = UIEdgeInsetsMake(20, 20, 40, 20);
    tv.textContainer.lineFragmentPadding = 0;

    // 把简易 Markdown 渲染成富文本（标题加粗放大、代码等宽）
    tv.attributedText = [self renderMarkdown:self.article.body];

    [self.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (NSAttributedString *)renderMarkdown:(NSString *)md {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];

    UIFont *body = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightRegular];
    UIFont *bodyBold = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightSemibold];
    UIFont *h2 = [SPTheme scaled:UIFontTextStyleTitle3 weight:UIFontWeightBold];
    UIFont *mono = [SPTheme mono:12.5];

    for (NSString *rawLine in [md componentsSeparatedByString:@"\n"]) {
        NSString *line = rawLine;
        NSAttributedString *piece = nil;

        if ([line hasPrefix:@"### "]) {
            piece = [[NSAttributedString alloc] initWithString:
                     [[line substringFromIndex:4] stringByAppendingString:@"\n"]
                attributes:@{NSFontAttributeName: bodyBold, NSForegroundColorAttributeName: [SPTheme text]}];
        } else if ([line hasPrefix:@"## "]) {
            piece = [[NSAttributedString alloc] initWithString:
                     [[line substringFromIndex:3] stringByAppendingString:@"\n"]
                attributes:@{NSFontAttributeName: h2, NSForegroundColorAttributeName: [SPTheme text]}];
        } else if ([line hasPrefix:@"- "] || [line hasPrefix:@"> "] || [line hasPrefix:@"1. "]) {
            piece = [[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                attributes:@{NSFontAttributeName: body,
                             NSForegroundColorAttributeName: [SPTheme textDim]}];
        } else if ([line hasPrefix:@"`"] && [line hasSuffix:@"`"] && line.length > 2) {
            piece = [[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                attributes:@{NSFontAttributeName: mono,
                             NSForegroundColorAttributeName: [SPTheme info]}];
        } else {
            piece = [[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                attributes:@{NSFontAttributeName: body,
                             NSForegroundColorAttributeName: [SPTheme text]}];
        }
        [out appendAttributedString:piece];
    }

    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 4;
    ps.paragraphSpacing = 2;
    [out addAttribute:NSParagraphStyleAttributeName value:ps
                range:NSMakeRange(0, out.length)];
    return out;
}

@end

#pragma mark - 列表

@interface SPHelpViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSArray<NSDictionary *> *groups;
@end

@implementation SPHelpViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"帮助";
    self.view.backgroundColor = [SPTheme background];

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

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    self.groups = [SPHelp groupedArticles];

    // 列表项交错入场（底部一排依次滑入）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSMutableArray *cells = [NSMutableArray array];
        for (UITableViewCell *c in self.table.visibleCells) [cells addObject:c];
        if (cells.count) [SPAnimationKit stagger:cells offset:10];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    NSString *kw = sc.searchBar.text ?: @"";
    if (!kw.length) {
        self.groups = [SPHelp groupedArticles];
    } else {
        NSArray *hits = [SPHelp search:kw];
        self.groups = hits.count ? @[@{@"category": @"搜索结果", @"items": hits}] : @[];
    }
    [self.table reloadData];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return self.groups.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    NSDictionary *g = self.groups[s];
    return [NSString stringWithFormat:@"%@（%lu）", g[@"category"],
            (unsigned long)[g[@"items"] count]];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return [self.groups[s][@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"h"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"h"];

    SPHelpArticle *a = self.groups[ip.section][@"items"][ip.row];
    cell.textLabel.text = a.title;
    cell.textLabel.font = [SPTheme scaled:UIFontTextStyleBody weight:UIFontWeightMedium];
    cell.detailTextLabel.text = a.summary;
    cell.detailTextLabel.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [SPTheme textDim];
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:a.symbol];
    cell.imageView.tintColor = [SPTheme accent];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SPHelpArticle *a = self.groups[ip.section][@"items"][ip.row];
    SPHelpArticleViewController *vc = [[SPHelpArticleViewController alloc] init];
    vc.article = a;
    [self.navigationController pushViewController:vc animated:YES];
}

@end
