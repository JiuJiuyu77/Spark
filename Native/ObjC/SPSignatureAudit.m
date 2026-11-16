//
//  SPSignatureAudit.m
//

#import "SPSignatureAudit.h"
#import "SPCompat.h"
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <unistd.h>

// Mach-O 常量（避免依赖更多系统头）
static const uint32_t kMHMagic64   = 0xfeedfacf;
static const uint32_t kMHCigam64   = 0xcffaedfe;
static const uint32_t kFATMagic    = 0xcafebabe;
static const uint32_t kFATCigam    = 0xbebafeca;
static const uint32_t kLC_CODE_SIGNATURE = 0x1d;
static const uint32_t kCSMAGIC_EMBEDDED_SIGNATURE = 0xfade0cc0;
static const uint32_t kCSMAGIC_CODEDIRECTORY      = 0xfade0c02;
static const uint32_t kCS_ADHOC = 0x2;

static uint32_t SPBE32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
         | ((uint32_t)p[2] << 8)  | (uint32_t)p[3];
}
static uint32_t SPLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

@implementation SPAuditIssue
@end

@implementation SPSignatureAudit

#pragma mark - 工具

+ (nullable NSData *)readFile:(NSString *)path maxBytes:(NSUInteger)cap {
    // 不用 NSFileHandle + @try/@catch：
    // 读失败时 NSFileHandle 会抛 NSException，catch 住之后对象状态不确定；
    // 直接用 map 方式读取，失败返回 nil，没有任何异常路径。
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if (!attrs) return nil;
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    if (size == 0) return nil;

    NSUInteger len = (NSUInteger)MIN(size, (unsigned long long)cap);
    void *buf = malloc(len);
    if (!buf) return nil;

    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) { free(buf); return nil; }
    ssize_t got = read(fd, buf, len);
    close(fd);
    if (got <= 0) { free(buf); return nil; }

    return [NSData dataWithBytesNoCopy:buf length:(NSUInteger)got freeWhenDone:YES];
}

+ (SPAuditIssue *)issue:(SPAuditLevel)level
                   path:(NSString *)rel
                summary:(NSString *)summary
                 detail:(nullable NSString *)detail
             suggestion:(nullable NSString *)suggestion {
    SPAuditIssue *i = [SPAuditIssue new];
    i.level = level;
    i.relativePath = rel ?: @"";
    i.summary = summary;
    i.detail = detail;
    i.suggestion = suggestion;
    return i;
}

#pragma mark - 单文件校验

+ (nullable SPAuditIssue *)verifyCodeSignatureOfMachO:(NSString *)path atRoot:(NSString *)root {
    NSString *rel = root.length ? [path substringFromIndex:MIN(path.length, root.length + 1)] : path.lastPathComponent;

    NSData *data = [self readFile:path maxBytes:NSUIntegerMax];
    if (!data || data.length < 32) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"文件过小或无法读取"
                    detail:nil suggestion:@"文件可能已损坏，重新下载安装包"];
    }

    const uint8_t *b = data.bytes;
    NSUInteger size = data.length;

    uint32_t magic = SPLE32(b);
    if (magic != kMHMagic64 && magic != kMHCigam64) {
        return nil;   // 不是 64 位 Mach-O，交给别处判断
    }

    uint32_t ncmds = SPLE32(b + 16);
    NSUInteger off = 32;
    BOOL foundSig = NO;
    uint32_t sigDataoff = 0, sigDatasize = 0;

    for (uint32_t i = 0; i < ncmds; i++) {
        if (off + 8 > size) {
            return [self issue:SPAuditLevelError path:rel
                       summary:@"load command 越界"
                        detail:[NSString stringWithFormat:@"第 %u 条命令读到文件外", i]
                    suggestion:@"文件被截断，重新下载"];
        }
        uint32_t cmd = SPLE32(b + off);
        uint32_t cmdsize = SPLE32(b + off + 4);
        if (cmdsize < 8 || off + cmdsize > size) {
            return [self issue:SPAuditLevelError path:rel
                       summary:@"load command 长度异常"
                        detail:[NSString stringWithFormat:@"cmd=0x%x cmdsize=%u", cmd, cmdsize]
                    suggestion:@"文件被截断，重新下载"];
        }
        if (cmd == kLC_CODE_SIGNATURE && off + 16 <= size) {
            foundSig = YES;
            sigDataoff  = SPLE32(b + off + 8);
            sigDatasize = SPLE32(b + off + 12);
        }
        off += cmdsize;
    }

    if (!foundSig) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"缺少代码签名（没有 LC_CODE_SIGNATURE）"
                    detail:nil
                suggestion:@"用 codesign --entitlements 重新签名该文件"];
    }

    if (sigDataoff > size) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"签名偏移超出文件大小（文件被截断）"
                    detail:[NSString stringWithFormat:
                            @"dataoff=%u 文件大小=%lu，差 %u 字节",
                            sigDataoff, (unsigned long)size, sigDataoff - (uint32_t)size]
                suggestion:@"重新下载安装包；或检查传输是否中断"];
    }
    if (sigDatasize == 0 || sigDataoff + sigDatasize > size) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"签名数据范围无效"
                    detail:[NSString stringWithFormat:@"dataoff=%u datasize=%u size=%lu",
                            sigDataoff, sigDatasize, (unsigned long)size]
                suggestion:@"重新签名"];
    }

    // SuperBlob
    const uint8_t *blob = b + sigDataoff;
    if (SPBE32(blob) != kCSMAGIC_EMBEDDED_SIGNATURE) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"签名 SuperBlob magic 不正确"
                    detail:[NSString stringWithFormat:@"0x%08x", SPBE32(blob)]
                suggestion:@"重新签名"];
    }
    uint32_t blobLen = SPBE32(blob + 4);
    uint32_t count   = SPBE32(blob + 8);
    if (blobLen < 12 || blobLen > sigDatasize) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"签名 SuperBlob 长度无效"
                    detail:[NSString stringWithFormat:@"len=%u datasize=%u", blobLen, sigDatasize]
                suggestion:@"重新签名"];
    }

    // 找主 CodeDirectory（slot 0）
    BOOL hasCD = NO;
    for (uint32_t i = 0; i < count; i++) {
        NSUInteger idxOff = 12 + i * 8;
        if (idxOff + 8 > blobLen) break;
        uint32_t slot  = SPBE32(blob + idxOff);
        uint32_t start = SPBE32(blob + idxOff + 4);
        if (slot != 0) continue;
        if (start + 44 > blobLen) continue;
        const uint8_t *cd = blob + start;
        if (SPBE32(cd) != kCSMAGIC_CODEDIRECTORY) continue;
        hasCD = YES;

        uint32_t cdSize   = SPBE32(cd + 4);
        uint32_t version  = SPBE32(cd + 8);
        uint32_t flags    = SPBE32(cd + 12);
        uint32_t hashOff  = SPBE32(cd + 16);
        uint32_t nSpecial = SPBE32(cd + 24);
        uint32_t nCode    = SPBE32(cd + 28);
        uint64_t limit    = SPBE32(cd + 32);

        if (!(flags & kCS_ADHOC)) {
            return [self issue:SPAuditLevelWarn path:rel
                       summary:@"签名不是 ad-hoc（flags 未置 CS_ADHOC）"
                        detail:[NSString stringWithFormat:@"flags=0x%x", flags]
                    suggestion:@"TrollStore 环境通常要求 ad-hoc 签名"];
        }
        if (version < 0x20001) {
            return [self issue:SPAuditLevelWarn path:rel
                       summary:@"CodeDirectory 版本过旧"
                        detail:[NSString stringWithFormat:@"0x%x", version]
                    suggestion:nil];
        }
        if (version >= 0x20300 && cdSize >= 64) {
            uint64_t large = ((uint64_t)SPBE32(cd + 56) << 32) | SPBE32(cd + 60);
            if (large) limit = large;
        }

        uint8_t hashType = cd[37];
        uint8_t pageLog  = cd[39];
        if (hashType != 2) {   // 2 = SHA-256
            return [self issue:SPAuditLevelWarn path:rel
                       summary:@"签名哈希算法不是 SHA-256"
                        detail:[NSString stringWithFormat:@"hashType=%u", hashType]
                    suggestion:nil];
        }
        if (pageLog == 0 || pageLog > 20) {
            return [self issue:SPAuditLevelError path:rel
                       summary:@"签名页大小异常"
                        detail:[NSString stringWithFormat:@"pageLog=%u", pageLog]
                    suggestion:@"重新签名"];
        }

        uint64_t page = 1ULL << pageLog;
        uint64_t expectSlots = (limit + page - 1) / page;
        if (limit != sigDataoff) {
            return [self issue:SPAuditLevelError path:rel
                       summary:@"签名覆盖范围与签名偏移不一致"
                        detail:[NSString stringWithFormat:@"limit=%llu dataoff=%u",
                                (unsigned long long)limit, sigDataoff]
                    suggestion:@"文件在签名后被修改，重新签名"];
        }
        if (hashOff > cdSize || nCode * 32 > cdSize - hashOff) {
            return [self issue:SPAuditLevelError path:rel
                       summary:@"CodeDirectory 哈希表越界"
                        detail:[NSString stringWithFormat:@"hashOff=%u cdSize=%u nCode=%u",
                                hashOff, cdSize, nCode]
                    suggestion:@"重新签名"];
        }

        // 逐页校验（这是 Dylix 的核心检查）
        NSUInteger check = (NSUInteger)MIN(expectSlots, (uint64_t)nCode);
        for (NSUInteger n = 0; n < check; n++) {
            uint64_t begin = (uint64_t)n * page;
            if (begin >= size) break;
            NSUInteger len = (NSUInteger)MIN(page, (uint64_t)size - begin);
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(b + begin, (CC_LONG)len, digest);
            if (memcmp(digest, cd + hashOff + n * 32, 32) != 0) {
                return [self issue:SPAuditLevelError path:rel
                           summary:@"签名页哈希不匹配（签名后被修改）"
                            detail:[NSString stringWithFormat:@"第 %lu 页不一致", (unsigned long)n]
                        suggestion:@"重新签名该文件"];
            }
        }
        break;
    }

    if (!hasCD) {
        return [self issue:SPAuditLevelError path:rel
                   summary:@"签名里没有主 CodeDirectory"
                    detail:nil suggestion:@"重新签名"];
    }
    return nil;   // 通过
}

#pragma mark - 目录审计

+ (NSArray<SPAuditIssue *> *)auditAppAtPath:(NSString *)appPath {
    NSMutableArray<SPAuditIssue *> *issues = [NSMutableArray array];

    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:appPath isDirectory:&isDir] || !isDir) {
        [issues addObject:[self issue:SPAuditLevelError path:appPath.lastPathComponent
                               summary:@"目录不存在" detail:nil suggestion:nil]];
        return issues;
    }

    NSMutableArray<NSString *> *stack = [NSMutableArray arrayWithObject:appPath];
    NSUInteger machoCount = 0;

    while (stack.count) {
        NSString *dir = stack.lastObject;
        [stack removeLastObject];

        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[];
        for (NSString *name in items) {
            NSString *full = [dir stringByAppendingPathComponent:name];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
            if (!attrs) continue;

            NSString *type = attrs[NSFileType];

            // 符号链接：ldid -s 会卡住
            if ([type isEqualToString:NSFileTypeSymbolicLink]) {
                [issues addObject:[self issue:SPAuditLevelError
                                        path:[full substringFromIndex:appPath.length + 1]
                                     summary:@"符号链接（ldid -s 会失败）"
                                      detail:attrs[NSFileTypeSymbolicLink] ?: nil
                                  suggestion:@"实体化成真实文件"]];
                continue;
            }

            if ([type isEqualToString:NSFileTypeDirectory]) {
                [stack addObject:full];

                // 空壳 bundle：Info.plist 的 CFBundleExecutable 指向不存在的文件
                NSString *plist = [full stringByAppendingPathComponent:@"Info.plist"];
                if ([fm fileExistsAtPath:plist]) {
                    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:plist];
                    NSString *exe = d[@"CFBundleExecutable"];
                    if (exe.length && ![fm fileExistsAtPath:[full stringByAppendingPathComponent:exe]]) {
                        [issues addObject:[self issue:SPAuditLevelError
                                                path:[plist substringFromIndex:appPath.length + 1]
                                             summary:@"空壳 bundle（CFBundleExecutable 不存在）"
                                              detail:[NSString stringWithFormat:@"期望 %@", exe]
                                          suggestion:@"删除该 Info.plist"]];
                    }
                }
                continue;
            }

            if (![type isEqualToString:NSFileTypeRegular]) continue;

            // 只看可能的二进制（读前 4 字节判断）
            NSData *head = [self readFile:full maxBytes:8];
            if (!head || head.length < 4) continue;
            uint32_t m32 = SPLE32(head.bytes);

            // FAT 包 ar（Theos vendor 的 libroot*.a）
            if (m32 == kFATMagic || m32 == kFATCigam) {
                NSString *rel = [full substringFromIndex:appPath.length + 1];
                if ([rel.pathExtension.lowercaseString isEqualToString:@"a"]) {
                    [issues addObject:[self issue:SPAuditLevelError path:rel
                                           summary:@"FAT 通用二进制内含 ar 静态库（ldid 处理不了）"
                                            detail:nil
                                        suggestion:@"移出 .app（编译不需要）"]];
                    continue;
                }
            }

            if (m32 != kMHMagic64 && m32 != kMHCigam64) continue;

            machoCount++;
            SPAuditIssue *issue = [self verifyCodeSignatureOfMachO:full atRoot:appPath];
            if (issue) [issues addObject:issue];
        }
    }

    if (!issues.count) {
        SPLog(@"签名审计通过：%lu 个 Mach-O 全部完好且签名一致", (unsigned long)machoCount);
    } else {
        SPLog(@"签名审计发现 %lu 个问题（共扫描 %lu 个 Mach-O）",
              (unsigned long)issues.count, (unsigned long)machoCount);
    }
    return issues;
}

+ (NSArray<SPAuditIssue *> *)auditPayloadAtPath:(NSString *)payloadPath {
    NSMutableArray<SPAuditIssue *> *all = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:payloadPath error:NULL] ?: @[];
    for (NSString *name in items) {
        if (![name hasSuffix:@".app"]) continue;
        [all addObjectsFromArray:[self auditAppAtPath:
            [payloadPath stringByAppendingPathComponent:name]]];
    }
    return all;
}

#pragma mark - 报告

+ (NSString *)reportForIssues:(NSArray<SPAuditIssue *> *)issues target:(NSString *)target {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"# 签名审计报告\n\n目标：`%@`\n\n", target];

    NSUInteger errors = 0, warns = 0;
    for (SPAuditIssue *i in issues) {
        if (i.level == SPAuditLevelError) errors++;
        else if (i.level == SPAuditLevelWarn) warns++;
    }

    if (!issues.count) {
        [s appendString:@"✅ 未发现问题。该包应当可以正常安装。\n"];
        return s;
    }

    [s appendFormat:@"共 **%lu 项错误**、%lu 项警告。\n\n",
        (unsigned long)errors, (unsigned long)warns];

    for (SPAuditIssue *i in issues) {
        [s appendFormat:@"## %@ %@\n\n",
            i.level == SPAuditLevelError ? @"❌" : @"⚠️",
            i.summary];
        if (i.relativePath.length) [s appendFormat:@"- 文件：`%@`\n", i.relativePath];
        if (i.detail.length)       [s appendFormat:@"- 详情：%@\n", i.detail];
        if (i.suggestion.length)   [s appendFormat:@"- 建议：%@\n", i.suggestion];
        [s appendString:@"\n"];
    }
    return s;
}

@end
