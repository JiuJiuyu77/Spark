//
//  SPHelp.h
//  Spark —— 内置帮助（参考 Dylix 的 HelpArticle）
//
//  为什么要有：巨魔环境下用户常常没有电脑，装完打开一看不知道从哪下手。
//  这里把「第一次怎么用」「为什么装不上」「常见报错怎么查」写进 App 内，
//  不依赖网络。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPHelpArticle : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *body;      // Markdown
@property (nonatomic, copy) NSString *category;  // 入门 / 编译 / 注入 / 排错 / 进阶
@end

@interface SPHelp : NSObject

/// 全部文章（按分类归组）
+ (NSArray<SPHelpArticle *> *)articles;

/// 按分类分组：@[@{@"category": @"入门", @"items": @[...]}]
+ (NSArray<NSDictionary *> *)groupedArticles;

/// 按标题模糊搜索
+ (NSArray<SPHelpArticle *> *)search:(NSString *)keyword;

@end

NS_ASSUME_NONNULL_END
