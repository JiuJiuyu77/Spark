//
//  SPLogView.m
//  日志视图 —— HIG：等宽字体 + 语义色分级 + 跟随系统深浅色；Gasp：新行淡入
//

#import "SPLogView.h"
#import "SPTheme.h"
#import "SPModels.h"
#import "SPCompat.h"

@interface SPLogCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *label;
@end

@implementation SPLogCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.font = [SPTheme mono:12];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:1],
            [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-1],
            [_label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        ]];
    }
    return self;
}

@end

@interface SPLogView () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate>
@property (nonatomic, strong) UICollectionView *collection;
@property (nonatomic, strong) NSMutableArray<SPLogLine *> *lines;
@property (nonatomic, strong) SPLogCell *sizingCell;
@property (nonatomic, assign) BOOL atBottom;
@property (nonatomic, strong) NSTimer *throttle;
@property (nonatomic, strong) UIButton *jumpToBottomButton;
/// 首次 layout 是否已完成。UICollectionView 在首次 layout 前做
/// performBatchUpdates 会直接 abort（不是抛异常，@try 拦不住），
/// 所以必须自己记录这个状态。
@property (nonatomic, assign) BOOL didLayoutOnce;
/// 布局完成后补一次刷新
@property (nonatomic, assign) BOOL needsReloadAfterLayout;
@end

@implementation SPLogView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _lines = [NSMutableArray array];
        _autoScroll = YES;
        _atBottom = YES;
        _fontSize = 12;
        _maxLines = 5000;
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [SPTheme codeBackground];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;
    layout.sectionInset = UIEdgeInsetsZero;

    _collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collection.translatesAutoresizingMaskIntoConstraints = NO;
    _collection.backgroundColor = [SPTheme codeBackground];
    _collection.dataSource = self;
    _collection.delegate = self;
    _collection.showsVerticalScrollIndicator = YES;
    _collection.alwaysBounceVertical = YES;
    _collection.indicatorStyle = UIScrollViewIndicatorStyleDefault;
    [_collection registerClass:SPLogCell.class forCellWithReuseIdentifier:@"log"];
    [self addSubview:_collection];
    [NSLayoutConstraint activateConstraints:@[
        [_collection.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_collection.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_collection.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_collection.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _sizingCell = [[SPLogCell alloc] initWithFrame:CGRectMake(0, 0, 320, 20)];
    _sizingCell.label.font = [SPTheme mono:_fontSize];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.didLayoutOnce && self.bounds.size.height > 0) {
        self.didLayoutOnce = YES;
        if (self.needsReloadAfterLayout) {
            self.needsReloadAfterLayout = NO;
            [self.collection reloadData];
            [self scrollToBottomAnimated:NO];
        }
    }
}

#pragma mark - 数据

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = MAX(9, MIN(20, fontSize));
    _sizingCell.label.font = [SPTheme mono:_fontSize];
    [_collection reloadData];
}

- (void)appendLine:(NSString *)line level:(SPLogLevel)level {
    [self appendLines:@[[SPLogLine lineWithText:line level:level]]];
}

- (void)appendLines:(NSArray<SPLogLine *> *)lines {
    if (!lines.count) return;

    NSInteger before = self.lines.count;
    [self.lines addObjectsFromArray:lines];

    BOOL trimmed = NO;
    if ((NSUInteger)self.lines.count > self.maxLines) {
        NSUInteger drop = (NSUInteger)self.lines.count - self.maxLines;
        [self.lines removeObjectsInRange:NSMakeRange(0, drop)];
        trimmed = YES;
    }

    // 为什么不能无条件 performBatchUpdates：
    //   UICollectionView 在首次 layout 之前（例如父控制器的 viewDidLoad 里）
    //   还没有完成内部初始批次计数。此时插入 N 个 item，UIKit 会认为
    //   「数据源数量与更新后数量不一致」，抛
    //     Invalid update: invalid number of items in section 0
    //   并直接 abort —— 这是真实发生过的崩溃。
    //
    // 因此只有满足以下条件才走增量插入：
    //   1. 已经被加到 window 上（view 有 superlayer）
    //   2. 已经完成过至少一次 layout
    //   3. 本次没有被裁剪（裁剪会整体前移，索引对不上，直接 reload）
    BOOL canBatch = !trimmed
                 && self.didLayoutOnce                       // 只有 layout 过了才敢批量更新
                 && _collection.window != nil
                 && before + (NSInteger)lines.count == (NSInteger)self.lines.count;

    if (canBatch) {
        // 关键：这里绝对不能用 @try/@catch 包 performBatchUpdates。
        // UICollectionView 抛 Invalid update 时它的内部批次状态已经损坏，
        // 即便我们 catch 住，UIKit 之后仍会 rethrow，
        // 最终走到 std::terminate → abort（真实崩溃日志：
        //   libdispatch → _ZSt9terminatev → abort，信号 6）。
        // 正确做法是把条件判断做足，保证根本不会进到非法状态。
        NSInteger expected = self.lines.count;
        NSInteger current = [_collection numberOfItemsInSection:0];
        // 双保险：数据源与 UIKit 记录的条目数必须完全吻合才敢增量更新
        if (current == before && before + (NSInteger)lines.count == expected) {
            NSMutableArray *ips = [NSMutableArray array];
            for (NSInteger i = before; i < expected; i++) {
                [ips addObject:[NSIndexPath indexPathForItem:i inSection:0]];
            }
            [_collection performBatchUpdates:^{
                [self->_collection insertItemsAtIndexPaths:ips];
            } completion:nil];
        } else {
            SPLog(@"条目数不一致（UIKit %ld / 数据源 %ld），改用 reloadData",
                  (long)current, (long)before);
            [_collection reloadData];
        }
    } else {
        [_collection reloadData];
        // 首次 layout 前调用 reloadData 是安全的（只是数据源变化），
        // 但滚动位置要等 layout 完成后再调
        if (!self.didLayoutOnce) self.needsReloadAfterLayout = YES;
    }
    [self scheduleAutoscroll];
}

- (void)clear {
    [self.lines removeAllObjects];
    [_collection reloadData];
    self.jumpToBottomButton.hidden = YES;
}

- (NSString *)fullText {
    NSMutableString *s = [NSMutableString string];
    for (SPLogLine *l in self.lines) {
        [s appendString:l.text];
        [s appendString:@"\n"];
    }
    return s;
}

#pragma mark - 自动滚动（Gasp：节流 + 温和回底）

- (void)scheduleAutoscroll {
    if (!self.autoScroll || !self.atBottom) {
        [self showJumpButton];
        return;
    }
    self.jumpToBottomButton.hidden = YES;
    if (self.throttle) return;
    __weak typeof(self) weakSelf = self;
    self.throttle = [NSTimer scheduledTimerWithTimeInterval:0.12 repeats:NO block:^(NSTimer *t) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.throttle = nil;
        [self scrollToBottomAnimated:NO];
    }];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (!self.lines.count) return;
    NSIndexPath *last = [NSIndexPath indexPathForItem:(NSInteger)self.lines.count - 1 inSection:0];
    if ([_collection numberOfItemsInSection:0] > last.item) {
        [_collection scrollToItemAtIndexPath:last atScrollPosition:UICollectionViewScrollPositionBottom animated:animated];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat bottom = scrollView.contentOffset.y + scrollView.bounds.size.height;
    self.atBottom = bottom > scrollView.contentSize.height - 40;
    if (self.atBottom) self.jumpToBottomButton.hidden = YES;
}

/// HIG：列表滚离底部时给一个明确的「回到底部」按钮，而不是靠猜
- (void)showJumpButton {
    if (!self.jumpToBottomButton) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
        cfg.title = @"最新";
        cfg.image = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
        cfg.imagePadding = 6;
        cfg.baseBackgroundColor = [SPTheme accent];
        cfg.baseForegroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor whiteColor] : [SPTheme text];
        }];
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
        b.configuration = cfg;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [b addTarget:self action:@selector(jumpToBottom) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [NSLayoutConstraint activateConstraints:@[
            [b.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [b.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        ]];
        self.jumpToBottomButton = b;
        b.alpha = 0;
    }
    if (self.jumpToBottomButton.hidden) {
        self.jumpToBottomButton.hidden = NO;
        [SPMotion appear:^{ self.jumpToBottomButton.alpha = 1; }];
    }
}

- (void)jumpToBottom {
    self.atBottom = YES;
    self.autoScroll = YES;
    [SPMotion disappear:^{ self.jumpToBottomButton.alpha = 0; } completion:^{
        self.jumpToBottomButton.hidden = YES;
    }];
    [self scrollToBottomAnimated:YES];
    [SPMotion hapticLight];
}

/// 轻量提示条（HIG：短暂、不阻挡、不弹窗）
- (void)showToast:(NSString *)text {
    if (!text.length) return;
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [SPTheme scaled:UIFontTextStyleFootnote weight:UIFontWeightMedium];
    l.textColor = [SPTheme text];
    l.backgroundColor = [SPTheme surface];
    l.textAlignment = NSTextAlignmentCenter;
    [SPTheme round:l radius:10];
    l.layer.borderWidth = 1;
    l.layer.borderColor = [SPTheme separator].CGColor;
    l.clipsToBounds = YES;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [l.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [l.heightAnchor constraintEqualToConstant:30],
    ]];
    l.alpha = 0;
    [SPMotion appear:^{ l.alpha = 1; }];
    [SPMotion disappear:^{ l.alpha = 0; } completion:^{ [l removeFromSuperview]; }];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.lines.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SPLogCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"log" forIndexPath:ip];
    SPLogLine *line = self.lines[ip.item];
    cell.label.font = [SPTheme mono:self.fontSize];
    cell.label.textColor = [SPTheme colorForLogLevel:line.level];
    cell.label.text = line.text.length ? line.text : @" ";

    if (self.highlightFilter.length) {
        NSRange r = [line.text rangeOfString:self.highlightFilter options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) {
            NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:line.text];
            [a addAttribute:NSBackgroundColorAttributeName
                       value:[[SPTheme warn] colorWithAlphaComponent:0.30] range:r];
            [a addAttribute:NSForegroundColorAttributeName value:[SPTheme text] range:NSMakeRange(0, a.length)];
            [a addAttribute:NSFontAttributeName value:[SPTheme mono:self.fontSize] range:NSMakeRange(0, a.length)];
            cell.label.attributedText = a;
        } else {
            cell.label.attributedText = nil;
        }
    } else {
        cell.label.attributedText = nil;
    }
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)ip {
    CGFloat width = cv.bounds.size.width;
    if (width <= 0) width = 320;
    self.sizingCell.label.font = [SPTheme mono:self.fontSize];
    self.sizingCell.label.text = self.lines[ip.item].text.length ? self.lines[ip.item].text : @" ";
    CGSize s = [self.sizingCell.contentView systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                                        withHorizontalFittingPriority:UILayoutPriorityRequired
                                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return CGSizeMake(width, MAX(16, ceil(s.height)));
}

#pragma mark - 深色/浅色切换

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    self.backgroundColor = [SPTheme codeBackground];
    self.collection.backgroundColor = [SPTheme codeBackground];
    [self.collection reloadData];
}

@end
