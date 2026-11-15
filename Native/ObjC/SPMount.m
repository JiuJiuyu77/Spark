//
//  SPMount.m
//

#import "SPMount.h"
#import "SPCompat.h"
#import <Security/Security.h>

static NSString *const kMountIndexFile = @"Spark.mounts";
static NSString *const kKeychainService = @"com.huging.spark.mount";

#pragma mark - SPMountEntry

@implementation SPMountEntry
@end

#pragma mark - SPMount

@implementation SPMount

- (instancetype)init {
    if ((self = [super init])) {
        _mountId = [[NSUUID UUID] UUIDString];
        _kind = SPMountKindWebDAV;
        _smbPort = 445;
        _autoMount = YES;
    }
    return self;
}

- (NSString *)kindString {
    return self.kind == SPMountKindWebDAV ? @"WebDAV" : @"SMB";
}

- (NSString *)localRootPath {
    NSString *base = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark/Mounts"];
    // 名字里可能有 / 等非法字符，做一下清洗
    NSString *safe = [self.displayName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [base stringByAppendingPathComponent:safe];
}

- (NSString *)descriptorPath {
    return [self.localRootPath stringByAppendingPathComponent:@".sparkmount"];
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.mountId ?: @"";
    d[@"name"] = self.displayName ?: @"";
    d[@"kind"] = @(self.kind);
    d[@"readOnly"] = @(self.readOnly);
    d[@"autoMount"] = @(self.autoMount);
    d[@"username"] = self.username ?: @"";
    if (self.kind == SPMountKindWebDAV) {
        d[@"baseURL"] = self.baseURL ?: @"";
    } else {
        d[@"smbHost"] = self.smbHost ?: @"";
        d[@"smbPort"] = @(self.smbPort);
        d[@"share"] = self.share ?: @"";
        d[@"smbDomain"] = self.smbDomain ?: @"";
    }
    return d;
}

+ (instancetype)mountFromDictionary:(NSDictionary *)d {
    SPMount *m = [SPMount new];
    if (![d isKindOfClass:NSDictionary.class]) return m;
    m.mountId = d[@"id"] ?: m.mountId;
    m.displayName = d[@"name"] ?: @"未命名";
    m.kind = [d[@"kind"] integerValue];
    m.readOnly = [d[@"readOnly"] boolValue];
    m.autoMount = d[@"autoMount"] ? [d[@"autoMount"] boolValue] : YES;
    m.username = d[@"username"];
    m.baseURL = d[@"baseURL"];
    m.smbHost = d[@"smbHost"];
    m.smbPort = [d[@"smbPort"] integerValue] ?: 445;
    m.share = d[@"share"];
    m.smbDomain = d[@"smbDomain"];
    return m;
}

@end

#pragma mark - SPMountManager

@interface SPMountManager ()
@property (nonatomic, strong) NSMutableArray<SPMount *> *internal;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation SPMountManager

+ (instancetype)shared {
    static SPMountManager *m; static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [SPMountManager new];
        m.internal = [NSMutableArray array];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 20;
        cfg.WaitsForConnectivity = NO;
        m.session = [NSURLSession sessionWithConfiguration:cfg];
        [m reload];
    });
    return m;
}

- (NSArray<SPMount *> *)mounts { return [self.internal copy]; }

#pragma mark 索引

- (NSString *)indexPath {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:kMountIndexFile];
}

- (void)reload {
    [self.internal removeAllObjects];
    NSData *d = [NSData dataWithContentsOfFile:self.indexPath];
    if (d) {
        NSArray *arr = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
        if ([arr isKindOfClass:NSArray.class]) {
            for (NSDictionary *j in arr) [self.internal addObject:[SPMount mountFromDictionary:j]];
        }
    }
    // 同时把根目录里的 .sparkmount 描述文件也扫一遍（手工拷进来的挂载也能识别）
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Spark/Mounts"];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL] ?: @[]) {
        NSString *desc = [[root stringByAppendingPathComponent:name] stringByAppendingPathComponent:@".sparkmount"];
        NSData *dd = [NSData dataWithContentsOfFile:desc];
        if (!dd) continue;
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:dd options:0 error:NULL];
        if (![j isKindOfClass:NSDictionary.class]) continue;
        SPMount *m = [SPMount mountFromDictionary:j];
        if (YES) {
            BOOL exists = NO;
            for (SPMount *x in self.internal) if ([x.mountId isEqualToString:m.mountId]) exists = YES;
            if (!exists) [self.internal addObject:m];
        }
    }
}

- (void)save {
    NSMutableArray *a = [NSMutableArray array];
    for (SPMount *m in self.internal) [a addObject:[m dictionaryRepresentation]];
    NSData *d = [NSJSONSerialization dataWithJSONObject:a options:NSJSONWritingPrettyPrinted error:NULL];
    [d writeToFile:self.indexPath atomically:YES];
}

- (void)addMount:(SPMount *)mount password:(NSString *)password {
    [self.internal addObject:mount];
    [self save];

    // 落地：目录 + 描述文件（文件浏览器据此识别为「已挂载」）
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:mount.localRootPath withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *desc = [NSJSONSerialization dataWithJSONObject:[mount dictionaryRepresentation]
                                                   options:NSJSONWritingPrettyPrinted error:NULL];
    [desc writeToFile:mount.descriptorPath atomically:YES];

    if (password.length) [self setPassword:password forMount:mount];
}

- (void)removeMount:(SPMount *)mount {
    [self.internal removeObject:mount];
    [self save];
    [[NSFileManager defaultManager] removeItemAtPath:mount.localRootPath error:NULL];
    [self deletePasswordForMount:mount];
}

#pragma mark Keychain

- (NSDictionary *)queryForMount:(SPMount *)mount {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: mount.mountId ?: @"",
    };
}

- (void)setPassword:(NSString *)password forMount:(SPMount *)mount {
    NSMutableDictionary *q = [[self queryForMount:mount] mutableCopy];
    SecItemDelete((__bridge CFDictionaryRef)q);
    q[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)q, NULL);
}

- (NSString *)passwordForMount:(SPMount *)mount {
    NSMutableDictionary *q = [[self queryForMount:mount] mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess) return nil;
    NSData *d = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

- (void)deletePasswordForMount:(SPMount *)mount {
    SecItemDelete((__bridge CFDictionaryRef)[self queryForMount:mount]);
}

#pragma mark - WebDAV

/// PROPFIND 请求，depth 0=单层 1=目录
- (NSURLRequest *)propfindRequest:(SPMount *)mount path:(NSString *)path depth:(NSInteger)depth {
    NSString *base = mount.baseURL ?: @"";
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    NSString *p = [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path;
    NSString *urlStr = [base stringByAppendingString:p];
    urlStr = [urlStr stringByAddingPercentEncodingWithAllowedCharacters:
              [NSCharacterSet URLFragmentAllowedCharacterSet]] ?: urlStr;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"PROPFIND";
    [req setValue:@"1" forHTTPHeaderField:@"Depth"];
    [req setValue:@"application/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    NSString *body = @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<d:propfind xmlns:d=\"DAV:\"><d:prop>"
        "<d:displayname/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/>"
        "</d:prop></d:propfind>";
    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    NSString *pw = [self passwordForMount:mount];
    if (mount.username.length) {
        NSString *token = [NSString stringWithFormat:@"%@:%@", mount.username, pw ?: @""];
        NSString *b64 = [[token dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        [req setValue:[@"Basic " stringByAppendingString:b64] forHTTPHeaderField:@"Authorization"];
    }
    return req;
}

/// 极简 XML 解析：够用（PROPFIND 返回结构固定），不引第三方库
- (NSArray<SPMountEntry *> *)parsePropfind:(NSData *)data requestPath:(NSString *)requestPath {
    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!xml) xml = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!xml.length) return @[];

    NSMutableArray *out = [NSMutableArray array];
    // 按 <d:response> / <D:response> 切块
    NSRegularExpression *blockRe = [NSRegularExpression regularExpressionWithPattern:
        @"<(?:\\w+:)?response\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?response>"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    NSArray *blocks = [blockRe matchesInString:xml options:0 range:NSMakeRange(0, xml.length)];

    NSString *(^unescape)(NSString *) = ^NSString *(NSString *s) {
        return [[[[[s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"]
                   stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"]
                  stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""]
                 stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"]
                stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    };

    for (NSTextCheckingResult *m in blocks) {
        NSString *block = [xml substringWithRange:[m rangeAtIndex:1]];

        // href
        NSString *href = nil;
        NSRegularExpression *hrefRe = [NSRegularExpression regularExpressionWithPattern:
            @"<(?:\\w+:)?href\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?href>"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        NSTextCheckingResult *hm = [hrefRe firstMatchInString:block options:0 range:NSMakeRange(0, block.length)];
        if (hm) href = unescape([block substringWithRange:[hm rangeAtIndex:1]]);

        // 跳过自身（目录本身）
        NSString *decodedHref = [href stringByRemovingPercentEncoding] ?: href ?: @"";
        NSString *normReq = [requestPath hasPrefix:@"/"] ? requestPath : [@"/" stringByAppendingString:requestPath];
        if (decodedHref.length && [decodedHref hasSuffix:@"/"]) {
            NSString *trim1 = [decodedHref substringToIndex:decodedHref.length - 1];
            if ([trim1 hasSuffix:normReq] || [trim1 isEqualToString:normReq]) continue;
        }

        BOOL isDir = [block rangeOfString:@"collection" options:NSCaseInsensitiveSearch].location != NSNotFound;

        NSString *name = nil;
        NSRegularExpression *nameRe = [NSRegularExpression regularExpressionWithPattern:
            @"<(?:\\w+:)?displayname\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?displayname>"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        NSTextCheckingResult *nm = [nameRe firstMatchInString:block options:0 range:NSMakeRange(0, block.length)];
        if (nm) name = unescape([block substringWithRange:[nm rangeAtIndex:1]]);
        if (!name.length && decodedHref.length) {
            NSString *h = [decodedHref hasSuffix:@"/"] ? [decodedHref substringToIndex:decodedHref.length - 1] : decodedHref;
            name = h.lastPathComponent;
        }
        if (!name.length) continue;

        SPMountEntry *e = [SPMountEntry new];
        e.name = name;
        e.path = decodedHref;
        e.isDirectory = isDir;

        NSRegularExpression *lenRe = [NSRegularExpression regularExpressionWithPattern:
            @"<(?:\\w+:)?getcontentlength\\b[^>]*>(\\d+)</(?:\\w+:)?getcontentlength>"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        NSTextCheckingResult *lm = [lenRe firstMatchInString:block options:0 range:NSMakeRange(0, block.length)];
        if (lm) e.size = [[block substringWithRange:[lm rangeAtIndex:1]] longLongValue];

        [out addObject:e];
    }
    // 目录在前，名字升序
    [out sortUsingComparator:^NSComparisonResult(SPMountEntry *a, SPMountEntry *b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedStandardCompare:b.name];
    }];
    return out;
}

- (void)listPath:(NSString *)remotePath
         ofMount:(SPMount *)mount
      completion:(void (^)(NSArray<SPMountEntry *> *, NSError *))completion {
    if (mount.kind != SPMountKindWebDAV) {
        NSError *e = SPError(SPErrorCodeUnsupported, @"SMB 需要 libsmbclient，本版本暂只支持 WebDAV");
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
        return;
    }
    NSURLRequest *req = [self propfindRequest:mount path:remotePath depth:1];
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (code >= 400) {
            NSError *e = SPError(SPErrorCodeIO, [NSString stringWithFormat:@"服务器返回 %ld，请检查地址/账号/权限", (long)code]);
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, e); });
            return;
        }
        NSArray *entries = [self parsePropfind:data requestPath:remotePath];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(entries, nil); });
    }] resume];
}

- (void)download:(NSString *)remotePath ofMount:(SPMount *)mount toLocal:(NSString *)localPath
      completion:(void (^)(BOOL, NSError *))completion {
    NSString *base = mount.baseURL ?: @"";
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    NSString *p = [remotePath hasPrefix:@"/"] ? [remotePath substringFromIndex:1] : remotePath;
    NSString *urlStr = [base stringByAppendingString:p];
    urlStr = [urlStr stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLFragmentAllowedCharacterSet] ?: urlStr;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    NSString *pw = [self passwordForMount:mount];
    if (mount.username.length) {
        NSString *token = [NSString stringWithFormat:@"%@:%@", mount.username, pw ?: @""];
        NSString *b64 = [[token dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        [req setValue:[@"Basic " stringByAppendingString:b64] forHTTPHeaderField:@"Authorization"];
    }
    [[self.session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *resp, NSError *err) {
        BOOL ok = NO; NSError *outErr = err;
        if (location && !err) {
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtPath:[localPath stringByDeletingLastPathComponent]
          withIntermediateDirectories:YES attributes:nil error:NULL];
            [fm removeItemAtPath:localPath error:NULL];
            ok = [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath] error:&outErr];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, outErr); });
    }] resume];
}

- (void)uploadLocal:(NSString *)localPath toRemote:(NSString *)remotePath mount:(SPMount *)mount
         completion:(void (^)(BOOL, NSError *))completion {
    if (mount.readOnly) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, SPError(SPErrorCodeIO, @"该挂载是只读的"));
        });
        return;
    }
    NSString *base = mount.baseURL ?: @"";
    if (![base hasSuffix:@"/"]) base = [base stringByAppendingString:@"/"];
    NSString *p = [remotePath hasPrefix:@"/"] ? [remotePath substringFromIndex:1] : remotePath;
    NSString *urlStr = [base stringByAppendingString:p];
    urlStr = [urlStr stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLFragmentAllowedCharacterSet] ?: urlStr;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"PUT";
    NSString *pw = [self passwordForMount:mount];
    if (mount.username.length) {
        NSString *token = [NSString stringWithFormat:@"%@:%@", mount.username, pw ?: @""];
        NSString *b64 = [[token dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        [req setValue:[@"Basic " stringByAppendingString:b64] forHTTPHeaderField:@"Authorization"];
    }
    NSURL *fileURL = [NSURL fileURLWithPath:localPath];
    [[self.session uploadTaskWithRequest:req fromFile:fileURL completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        BOOL ok = !err && code >= 200 && code < 300;
        NSError *e = ok ? nil : (err ?: SPError(SPErrorCodeIO, [NSString stringWithFormat:@"上传失败 HTTP %ld", (long)code]));
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, e); });
    }] resume];
}

- (void)testMount:(SPMount *)mount completion:(void (^)(BOOL, NSString *))completion {
    [self listPath:@"/" ofMount:mount completion:^(NSArray<SPMountEntry *> *entries, NSError *error) {
        if (error) { if (completion) completion(NO, error.localizedDescription); return; }
        if (completion) completion(YES, [NSString stringWithFormat:@"连接正常，根目录 %lu 项", (unsigned long)entries.count]);
    }];
}

@end
