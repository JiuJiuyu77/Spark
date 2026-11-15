//
//  SPAutofix.h
//  Spark —— 从编译日志解析可自动修复的问题（参考 Dylix 的 CompatibilityRepair）
//
//  思路：
//   1. 从编译日志里抽出 `file:line:col: error: msg`
//   2. 用内置规则匹配（只收最常见、最安全的几条）
//   3. 生成「改动计划」：每条带 before/after 快照，**只预览不写入**
//   4. 用户确认后按计划改文件；原文件备份为 .sparkbak
//   5. 支持一键撤销
//
//  刻意只做「改一行/加一行」这类低风险修复，不做语义级重构。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPFixIt : NSObject
/// 规则标识（例如 missing-semicolon）
@property (nonatomic, copy) NSString *ruleId;
/// 规则显示名
@property (nonatomic, copy) NSString *ruleName;
/// 绝对路径
@property (nonatomic, copy) NSString *filePath;
/// 1-based 行号
@property (nonatomic, assign) NSInteger line;
/// 修改前的整行
@property (nonatomic, copy) NSString *beforeText;
/// 修改后的整行
@property (nonatomic, copy) NSString *afterText;
/// 为什么这么改
@property (nonatomic, copy) NSString *reason;
/// 是否高置信度（低风险才允许一键应用）
@property (nonatomic, assign) BOOL safe;
@end

@interface SPAutofix : NSObject

/// 从一段编译日志解析出可修复项
+ (NSArray<SPFixIt *> *)parseLog:(NSString *)logText projectRoot:(NSString *)root;

/// 应用这些修复（会写文件，原文件备份为 <file>.sparkbak）
+ (BOOL)applyFixes:(NSArray<SPFixIt *> *)fixes error:(NSError *_Nullable *_Nullable)error;

/// 撤销某个文件的上一次修复
+ (BOOL)revertFile:(NSString *)path error:(NSError *_Nullable *_Nullable)error;

/// 是否有备份可撤销
+ (BOOL)canRevert:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
