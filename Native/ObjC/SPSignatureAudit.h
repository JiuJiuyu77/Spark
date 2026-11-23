//
//  SPSignatureAudit.h
//  Workbench —— 签名审计（参考 Dylix 的 DylibSignature 思路）
//
//  为什么需要它：
//   .ipa 装不上时，TrollStore 只给一句 "ldid: Unknown header magic"，
//   不告诉你是哪个文件、哪一项坏了。本项目为此排查了 7 轮。
//   这里把「装不上」的原因变成可读的检查报告：
//
//     · 文件是否被截断（LC_CODE_SIGNATURE 的 dataoff 越界）
//     · 是否缺少签名段
//     · CodeDirectory 与文件内容是否一致（逐页 SHA-256 校验）
//     · 是否是 FAT 包 ar 这类 ldid 处理不了的格式
//     · 符号链接 / 空壳 bundle（ldid -s 会卡住的两类）
//
//  与 Dylix 的区别：
//   它只校验「签出的 dylib 是否合法」，我们校验整个 .app/ipa，
//   因为 Workbench 的痛点是在安装阶段而不是产出阶段。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPAuditLevel) {
    SPAuditLevelOK = 0,
    SPAuditLevelWarn,
    SPAuditLevelError,
};

@interface SPAuditIssue : NSObject
@property (nonatomic, assign) SPAuditLevel level;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, copy) NSString *summary;      // 一句话结论
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, copy, nullable) NSString *suggestion;
@end

@interface SPSignatureAudit : NSObject

/// 审计一个 .app 目录（或解包后的 Payload 目录）
+ (NSArray<SPAuditIssue *> *)auditAppAtPath:(NSString *)appPath;

/// 审计整个解包 ipa 的 Payload 目录
+ (NSArray<SPAuditIssue *> *)auditPayloadAtPath:(NSString *)payloadPath;

/// 生成可读报告（Markdown）
+ (NSString *)reportForIssues:(NSArray<SPAuditIssue *> *)issues
                       target:(NSString *)target;

/// 给单个 Mach-O 做逐页签名一致性校验（Dylix 同款思路）
+ (nullable SPAuditIssue *)verifyCodeSignatureOfMachO:(NSString *)path
                                               atRoot:(NSString *)root;

@end

NS_ASSUME_NONNULL_END
