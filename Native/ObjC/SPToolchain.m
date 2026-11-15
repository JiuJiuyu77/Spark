//
//  SPToolchain.m
//

#import "SPToolchain.h"
#import "SPCompat.h"

static NSString *const kDefaultsHomeRoot = @"Spark.homeRoot";
static NSString *const kDefaultsReinRoot = @"Spark.reinRoot";

#pragma mark - SPToolchainProfile

@implementation SPToolchainProfile

- (instancetype)init {
    if ((self = [super init])) { _sdkName = @"iPhoneOS16.5.sdk"; _sshPort = 22; _name = @"本机"; }
    return self;
}

- (NSDictionary<NSString *, NSString *> *)extraEnvironment {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (self.theosPath.length) env[@"THEOS"] = self.theosPath;
    if (self.sdkPath.length) {
        env[@"THEOS_SDK"] = self.sdkPath;
        env[@"SYSROOT"] = self.sdkPath;
    }
    if (self.ollvmRoot.length) {
        // 与 Rein 的 harness 注入命名保持一致
        env[@"CA_TOOL_OLLVM_ROOT"] = self.ollvmRoot;
        env[@"CA_TOOL_OLLVM_CLANG"] = [self.ollvmRoot stringByAppendingPathComponent:@"bin/clang"];
        env[@"CA_TOOL_OLLVM_RESOURCE_DIR"] = [self.ollvmRoot stringByAppendingPathComponent:@"lib/clang/16"];
    }
    if (self.darwinBinDir.length) {
        env[@"THEOS_TOOLCHAIN"] = self.darwinBinDir;
    }
    env[@"SP_PROFILE"] = self.name ?: @"";
    env[@"SP_TARGET"] = self.target == SPBuildTargetDevice ? @"device"
                       : (self.target == SPBuildTargetRemote ? @"remote" : @"ci");
    if (self.sshHost.length) env[@"SP_SSH_HOST"] = self.sshHost;
    return env;
}

@end

#pragma mark - SPToolchainScan

@interface SPToolchainScan ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *found;
@end

@implementation SPToolchainScan

- (instancetype)init {
    if ((self = [super init])) { _found = [NSMutableDictionary dictionary]; }
    return self;
}

- (void)setPath:(nullable NSString *)path for:(SPToolchainComponent)c {
    self.found[@(c)] = path ?: @"";
}

- (BOOL)has:(SPToolchainComponent)c {
    return [self pathFor:c].length > 0;
}

- (NSString *)pathFor:(SPToolchainComponent)c {
    return self.found[@(c)] ?: @"";
}

static NSString *const kNames[] = {@"Theos", @"SDK", @"Darwin 工具", @"OLLVM", @"逆向工具", @"Python", @"Node", @"SSH"};
static NSString *const kMarks[] = {@"✓", @"✗"};

- (NSString *)summary {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSInteger i = 0; i < SPToolchainComponentCount; i++) {
        NSString *name = i < (NSInteger)(sizeof(kNames) / sizeof(kNames[0])) ? kNames[i] : @"?";
        [parts addObject:[NSString stringWithFormat:@"%@ %@", name, kMarks[[self has:(SPToolchainComponent)i] ? 0 : 1]]];
    }
    return [parts componentsJoinedByString:@"  "];
}

- (NSArray<NSString *> *)remedies {
    NSMutableArray *r = [NSMutableArray array];
    if (![self has:SPToolchainComponentTheos])
        [r addObject:@"未找到 Theos：点「探测 Rein 目录」或把 theos 放到 Rein/tools/theos-local。"];
    if (![self has:SPToolchainComponentSDK])
        [r addObject:@"未找到 iPhoneOS*.sdk：可在「工具链 → SDK 商店」里下载，或安装到 theos/sdks。"];
    if (![self has:SPToolchainComponentDarwin] && [self has:SPToolchainComponentTheos])
        [r addObject:@"真机编译需要 Darwin 版 clang/ld64/ldid（Rein 的 theos-root/usr/bin 里有一套）。"];
    if (![self has:SPToolchainComponentOLLVM])
        [r addObject:@"OLLVM 未安装：不开混淆不影响普通构建，需要时安装 Arkari LLVM 16。"];
    if (![self has:SPToolchainComponentReverse])
        [r addObject:@"逆向工具（radare2/mt-macho）未安装：签名分析、注入 dylib 会不可用。"];
    return r;
}

@end

#pragma mark - SPToolchain

@interface SPToolchain ()
@property (nonatomic, strong) SPToolchainScan *scan;
@property (nonatomic, copy, nullable) NSString *resolvedDarwin;
@property (nonatomic, copy, nullable) NSString *resolvedOLLVM;
@property (nonatomic, copy, nullable) NSString *resolvedReverse;
@property (nonatomic, copy, nullable) NSString *resolvedPython;
@property (nonatomic, copy, nullable) NSString *resolvedNode;
@property (nonatomic, copy, nullable) NSString *resolvedSSH;
@end

@implementation SPToolchain

+ (instancetype)shared {
    static SPToolchain *t; static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = [SPToolchain new];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        t.reinRoot = [d stringForKey:kDefaultsReinRoot] ?: @"/var/mobile/Documents/Rein";
        t.homeRoot = [d stringForKey:kDefaultsHomeRoot];
        [t rescan];
    });
    return t;
}

- (void)setReinRoot:(NSString *)reinRoot {
    _reinRoot = [reinRoot copy];
    [NSUserDefaults.standardUserDefaults setObject:reinRoot forKey:kDefaultsReinRoot];
}

- (void)setHomeRoot:(NSString *)homeRoot {
    _homeRoot = [homeRoot copy];
    if (homeRoot.length) [NSUserDefaults.standardUserDefaults setObject:homeRoot forKey:kDefaultsHomeRoot];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kDefaultsHomeRoot];
}

#pragma mark 候选根目录

- (NSArray<NSString *> *)candidateRoots {
    NSMutableArray *roots = [NSMutableArray array];
    if (self.homeRoot.length) [roots addObject:self.homeRoot];
    if (self.reinRoot.length) [roots addObject:self.reinRoot];
    // App 包内（Rein 把 theos-root 一起打进了 DSH.app）
    NSString *bundle = [NSBundle mainBundle].bundlePath;
    [roots addObject:bundle];
    return roots;
}

/// 依次尝试 "<root>/<rel>"，返回第一个存在且是目录的
- (nullable NSString *)firstExistingDirectory:(NSArray<NSString *> *)rels fromRoots:(NSArray<NSString *> *)roots {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        for (NSString *rel in rels) {
            NSString *p = rel.length ? [root stringByAppendingPathComponent:rel] : root;
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) return p;
        }
    }
    return nil;
}

- (nullable NSString *)firstExistingFile:(NSArray<NSString *> *)rels fromRoots:(NSArray<NSString *> *)roots {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        for (NSString *rel in rels) {
            NSString *p = [root stringByAppendingPathComponent:rel];
            if ([fm isExecutableFileAtPath:p]) return p;
        }
    }
    return nil;
}

#pragma mark 扫描

- (void)rescan {
    SPToolchainScan *scan = [SPToolchainScan new];
    NSArray *roots = [self candidateRoots];
    NSFileManager *fm = NSFileManager.defaultManager;

    // 1) Theos：tools/theos-local、tools/theos-full、theos-root/theos、…/theos
    NSString *theos = [self firstExistingDirectory:@[@"tools/theos-full", @"tools/theos-local",
                                                     @"theos-root/theos", @"theos", @"tools/theos-root/theos",
                                                     @"Theos"] fromRoots:roots];
    if (!theos) {
        // 包内 DSH.app/theos-root/theos 可能只读，但也能用
        NSString *alt = [self firstExistingDirectory:@[@"theos-root/theos"] fromRoots:@[[NSBundle mainBundle].bundlePath]];
        theos = alt;
    }
    [scan setPath:theos for:SPToolchainComponentTheos];

    // 2) SDK
    NSString *sdk = nil;
    if (theos) {
        NSString *sdks = [theos stringByAppendingPathComponent:@"sdks"];
        sdk = [self firstExistingDirectory:[self sdkNamesInDirectory:sdks] fromRoots:@[sdks]];
    }
    if (!sdk) {
        NSString *store = [self firstExistingDirectory:@[@"sdks-store"] fromRoots:roots];
        if (store) sdk = [self firstExistingDirectory:[self sdkNamesInDirectory:store] fromRoots:@[store]];
    }
    [scan setPath:sdk for:SPToolchainComponentSDK];

    // 3) Darwin bin：theos-root/usr/bin / helpers（真机可执行）
    NSString *darwin = [self firstExistingDirectory:@[@"tools/theos-root/usr/bin"] fromRoots:roots];
    if (!darwin) darwin = [self firstExistingDirectory:@[@"helpers"] fromRoots:[@[[NSBundle mainBundle].bundlePath] arrayByAddingObjectsFromArray:roots]];
    // 至少要真有 clang/ld64 才算
    if (darwin && ![[darwin stringByAppendingPathComponent:@"ld64"] isKindOfClass:NSNull.class]
        && ![fm fileExistsAtPath:[darwin stringByAppendingPathComponent:@"ld64"]]
        && ![fm fileExistsAtPath:[darwin stringByAppendingPathComponent:@"clang-16"]]
        && ![fm fileExistsAtPath:[darwin stringByAppendingPathComponent:@"clang"]]) {
        darwin = nil;
    }
    self.resolvedDarwin = darwin;
    [scan setPath:darwin for:SPToolchainComponentDarwin];

    // 4) OLLVM
    NSString *ollvm = [self firstExistingDirectory:@[@"tools/ollvm", @"ollvm"] fromRoots:roots];
    if (ollvm && ![fm fileExistsAtPath:[ollvm stringByAppendingPathComponent:@"bin/clang"]]) ollvm = nil;
    self.resolvedOLLVM = ollvm;
    [scan setPath:ollvm for:SPToolchainComponentOLLVM];

    // 5) 逆向工具
    NSString *rev = [self firstExistingDirectory:@[@"tools/reverse/bin"] fromRoots:roots];
    if (rev && ![fm fileExistsAtPath:[rev stringByAppendingPathComponent:@"rabin2"]] &&
        ![fm fileExistsAtPath:[rev stringByAppendingPathComponent:@"mt-macho"]]) rev = nil;
    self.resolvedReverse = rev;
    [scan setPath:rev for:SPToolchainComponentReverse];

    // 6) python / node / ssh
    self.resolvedPython = [self firstExistingFile:@[@"tools/python/python3", @"tools/python/python", @"bin/python3"] fromRoots:roots];
    [scan setPath:self.resolvedPython for:SPToolchainComponentPython];

    self.resolvedNode = [self firstExistingFile:@[@"bin/node22", @"bin/node", @"helpers/node"] fromRoots:roots];
    [scan setPath:self.resolvedNode for:SPToolchainComponentNode];

    self.resolvedSSH = [SPUtil findExecutable:@[@"ssh"] searchDirs:@[@"/usr/bin", @"/usr/local/bin", @"/bin", @"/var/jb/usr/bin"]];
    [scan setPath:self.resolvedSSH for:SPToolchainComponentDevices];

    self.scan = scan;
    SPDebug(@"scan: %@", [scan summary]);
}

- (NSArray<NSString *> *)sdkNamesInDirectory:(NSString *)dir {
    NSMutableArray *names = [NSMutableArray array];
    NSArray *all = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:NULL] ?: @[];
    for (NSString *n in all) {
        if ([n hasSuffix:@".sdk"] && [n hasPrefix:@"iPhoneOS"]) [names addObject:n];
    }
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)availableSDKs {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *roots = [self candidateRoots];
    for (NSString *root in roots) {
        for (NSString *rel in @[@"tools/theos-full/sdks", @"tools/theos-local/sdks", @"sdks-store", @"sdks"]) {
            NSString *dir = [root stringByAppendingPathComponent:rel];
            BOOL isDir = NO;
            if ([NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&isDir] && isDir) {
                for (NSString *n in [self sdkNamesInDirectory:dir]) if (![out containsObject:n]) [out addObject:n];
            }
        }
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

- (nullable NSString *)resolvedSDKPathNamed:(nullable NSString *)sdkName {
    NSString *name = sdkName.length ? sdkName : nil;
    NSArray *roots = [self candidateRoots];
    for (NSString *root in roots) {
        for (NSString *rel in @[@"tools/theos-full/sdks", @"tools/theos-local/sdks", @"sdks-store", @"theos/sdks"]) {
            NSString *base = [root stringByAppendingPathComponent:rel];
            if (name) {
                NSString *p = [base stringByAppendingPathComponent:name];
                BOOL isDir = NO;
                if ([NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&isDir] && isDir) return p;
            } else {
                NSString *first = [self sdkNamesInDirectory:base].lastObject; // 取最新版本
                if (first) return [base stringByAppendingPathComponent:first];
            }
        }
    }
    return nil;
}

#pragma mark Profile

- (SPToolchainProfile *)localProfileWithSDK:(NSString *)sdkName error:(NSError **)error {
    [self rescan];
    SPToolchainProfile *p = [SPToolchainProfile new];
    p.target = SPBuildTargetDevice;
    p.name = @"本机";
    p.theosPath = [self.scan pathFor:SPToolchainComponentTheos].length ? [self.scan pathFor:SPToolchainComponentTheos] : nil;
    p.darwinBinDir = self.resolvedDarwin;
    p.ollvmRoot = self.resolvedOLLVM;
    p.reverseBinDir = self.resolvedReverse;
    p.python3 = self.resolvedPython;
    p.node = self.resolvedNode;
    p.sdkPath = [self resolvedSDKPathNamed:sdkName];
    p.sdkName = p.sdkPath.lastPathComponent ?: (sdkName ?: @"");
    if (!p.theosPath) {
        if (error) *error = SPError(SPErrorCodeMissingToolchain,
            @"没找到 Theos。请把 Theos 安装到 Rein/tools/theos-local，或在设置里指定安装目录。");
        return nil;
    }
    if (!p.sdkPath) {
        if (error) *error = SPError(SPErrorCodeMissingToolchain,
            @"没找到 iPhoneOS SDK。可从 Rein 的 sdks-store 复制，或在工具链页下载。");
        return nil;
    }
    return p;
}

- (SPToolchainProfile *)remoteProfileWithHost:(NSString *)host
                                         user:(NSString *)user
                                         port:(NSInteger)port
                                          sdk:(NSString *)sdkName {
    SPToolchainProfile *p = [SPToolchainProfile new];
    p.target = SPBuildTargetRemote;
    p.name = [NSString stringWithFormat:@"远程 %@@%@", user.length ? user : @"mobile", host];
    p.sshHost = host; p.sshUser = user.length ? user : @"mobile"; p.sshPort = port ?: 22;
    p.sdkName = sdkName ?: @"";
    // 远程的路径由远端决定，这里只留空让远端自己探测
    return p;
}

- (SPToolchainProfile *)ciProfileWithSDK:(NSString *)sdkName {
    SPToolchainProfile *p = [SPToolchainProfile new];
    p.target = SPBuildTargetCI;
    p.name = @"GitHub CI";
    p.sdkName = sdkName ?: @"iPhoneOS16.5.sdk";
    return p;
}

- (NSString *)pathPrefixForProfile:(SPToolchainProfile *)profile {
    NSMutableArray *dirs = [NSMutableArray array];
    if (profile.darwinBinDir.length) [dirs addObject:profile.darwinBinDir];
    if (profile.theosPath.length) [dirs addObject:[profile.theosPath stringByAppendingPathComponent:@"bin"]];
    // 真机上的系统目录优先于 xbin
    [dirs addObjectsFromArray:@[@"/var/jb/usr/bin", @"/usr/bin", @"/usr/local/bin", @"/bin", @"/usr/sbin", @"/sbin"]];
    return [dirs componentsJoinedByString:@":"];
}

@end
