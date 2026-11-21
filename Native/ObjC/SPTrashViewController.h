//
//  SPTrashViewController.h
//  Spark —— 项目回收站（对齐 dylix 的 trashMode）
//
//  行为约定与 dylix 的 ProjectTrash 一致：
//    · 每个条目目录里有 .studio-trash.json（deletedAt / originalPath）
//    · 保留 7 天，过期由 TMCPruneProjectTrash 自动清理
//    · 支持「恢复」与「彻底删除」
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPTrashViewController : UITableViewController

/// 列表变化（恢复/删除）后回调，让项目页刷新
@property (nonatomic, copy, nullable) void (^onChange)(void);

@end

NS_ASSUME_NONNULL_END