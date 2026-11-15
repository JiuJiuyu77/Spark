//
//  SPLogView.m
//

#import "SPLogView.h"
#import "SPTheme.h"

@interface SPLogCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *label;
@end

@implementation SPLogCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.font = [SPTheme monoFont:11.5];
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
@property (nonatomic, weak) SPLogCell *sizingCell;
@property (nonatomic, assign) BOOL autoScroll;
@property (nonatomic, assign) BOOL atBottom;
@property (nonatomic, strong) NSTimer *throttle;
@property (nonatomic, strong) UIView *toastView;
@end

@implementation SPLogView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _lines = [NSMutableArray array];
        _autoScroll = YES;
        _atBottom = YES;
        _fontSize = 11.5;
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
    [_collection registerClass:SPLogCell.class forCellWithReuseIdentifier:@"log"];
    [self addSubview:_collection];
    [NSLayoutConstraint activateConstraints:@[
        [_collection.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_collection.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_collection.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_collection.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _sizingCell = [[SPLogCell alloc] initWithFrame:CGRectMake(0, 0, 320, 20)];
    _sizingCell.label.font = [SPTheme monoFont:_fontSize];
}

#pragma mark - 数据

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = MAX(9, MIN(18, fontSize));
    _sizingCell.label.font = [SPTheme monoFont:_fontSize];
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
    if (self.lines.count > (NSInteger)self.maxLines) {
        NSInteger drop = self.lines.count - (NSInteger)self.maxLines;
        [self.lines removeObjectsInRange:NSMakeRange(0, drop)];
        trimmed = YES;
    }

    if (trimmed) {
        [_collection reloadData];
    } else {
        NSMutableArray *ips = [NSMutableArray array];
        for (NSInteger i = before; i < self.lines.count; i++) [ips addObject:[NSIndexPath indexPathForItem:i inSection:0]];
        [_collection performBatchUpdates:^{
            [self->_collection insertItemsAtIndexPaths:ips];
        } completion:nil];
    }

    [self scheduleAutoscroll];
}

- (void)clear {
    [self.lines removeAllObjects];
    [_collection reloadData];
}

- (NSString *)fullText {
    NSMutableString *s = [NSMutableString string];
    for (SPLogLine *l in self.lines) { [s appendString:l.text]; [s appendString:@"\n"]; }
    return s;
}

#pragma mark - 自动滚动（节流）

- (void)scheduleAutoscroll {
    if (!self.autoScroll || !self.atBottom) { [self maybeShowNewLineHint]; return; }
    if (self.throttle) return;
    __weak typeof(self) weakSelf = self;
    self.throttle = [NSTimer scheduledTimerWithTimeInterval:0.12 repeats:NO block:^(NSTimer *t) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.throttle = nil;
        [self scrollToBottomAnimated:NO];
    }];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.lines.count == 0) return;
    NSIndexPath *last = [NSIndexPath indexPathForItem:self.lines.count - 1 inSection:0];
    if ([_collection numberOfItemsInSection:0] > last.item) {
        [_collection scrollToItemAtIndexPath:last atScrollPosition:UICollectionViewScrollPositionBottom animated:animated];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offset = scrollView.contentOffset.y + scrollView.bounds.size.height;
    self.atBottom = offset > scrollView.contentSize.height - 40;
}

- (void)maybeShowNewLineHint {
    if (!self.toastView) {
        UILabel *l = [[UILabel alloc] init];
        l.text = @"↓ 有新日志（点击回到底部）";
        l.font = [SPTheme uiFont:11 weight:UIFontWeightMedium];
        l.textColor = [SPTheme background];
        l.backgroundColor = [SPTheme accent];
        l.textAlignment = NSTextAlignmentCenter;
        l.layer.cornerRadius = 12;
        l.layer.cornerCurve = kCACornerCurveContinuous;
        l.clipsToBounds = YES;
        l.userInteractionEnabled = YES;
        [l addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bottomTapped)]];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [l.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [l.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
            [l.heightAnchor constraintEqualToConstant:24],
            [l.widthAnchor constraintEqualToConstant:190],
        ]];
        self.toastView = l;
    }
    self.toastView.hidden = NO;
}

- (void)bottomTapped {
    self.toastView.hidden = YES;
    self.atBottom = YES;
    self.autoScroll = YES;
    [self scrollToBottomAnimated:YES];
}

- (void)showToast:(NSString *)text {
    if (!text.length) return;
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [SPTheme uiFont:12 weight:UIFontWeightMedium];
    l.textColor = [SPTheme text];
    l.backgroundColor = [[SPTheme surfaceHigh] colorWithAlphaComponent:0.95];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.cornerRadius = 10;
    l.clipsToBounds = YES;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [l.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [l.heightAnchor constraintEqualToConstant:28],
    ]];
    l.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:1.4 options:0 animations:^{ l.alpha = 0; }
                         completion:^(BOOL done) { [l removeFromSuperview]; }];
    }];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.lines.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SPLogCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"log" forIndexPath:ip];
    SPLogLine *line = self.lines[ip.item];
    cell.label.font = [SPTheme monoFont:self.fontSize];
    cell.label.textColor = [SPTheme colorForLogLevel:line.level];
    cell.label.text = line.text.length ? line.text : @" ";

    if (self.highlightFilter.length) {
        NSRange r = [line.text rangeOfString:self.highlightFilter options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) {
            NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:line.text];
            [a addAttribute:NSBackgroundColorAttributeName
                       value:[[SPTheme warn] colorWithAlphaComponent:0.35] range:r];
            [a addAttribute:NSForegroundColorAttributeName value:[SPTheme text] range:NSMakeRange(0, a.length)];
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
    self.sizingCell.label.font = [SPTheme monoFont:self.fontSize];
    self.sizingCell.label.text = self.lines[ip.item].text.length ? self.lines[ip.item].text : @" ";
    CGSize s = [self.sizingCell.contentView systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                                        withHorizontalFittingPriority:UILayoutPriorityRequired
                                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return CGSizeMake(width, MAX(16, ceil(s.height)));
}

@end
