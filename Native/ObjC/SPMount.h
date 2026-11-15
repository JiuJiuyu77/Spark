//
//  SPMount.h
//  Spark —— 外部文件夹挂载（WebDAV / SMB）
//
//  设计：
//   · 不依赖 iSH 或任何系统挂载命令，协议由 App 自己实现（TrollStore 环境下
//     有完整文件权限，可以直接读写任意路径）
//   · 「挂载」= 在 Documents/Spark/Mounts/<名字>/ 下放一个 .sparkmount 描述文件，
//     文件浏览器看到它就走远端列目录，读写也是转成协议请求
//   · 凭据存 Keychain（不落 JSON）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPMountKind) {
    SPMountKindWebDAV = 0,
    SPMountKindSMB,
};

/// 一个远端条目
@interface SPMountEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;      // 远端相对路径
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, strong, nullable) NSDate *modified;
@end

/// 挂载配置（可 JSON 序列化；密码走 Keychain）
@interface SPMount : NSObject

@property (nonatomic, copy) NSString *mountId;     // UUID
@property (nonatomic, copy) NSString *displayName; // 本地显示名
@property (nonatomic, assign) SPMountKind kind;

// WebDAV
@property (nonatomic, copy, nullable) NSString *baseURL;   // https://host:port/dav
// SMB
@property (nonatomic, copy, nullable) NSString *smbHost;   // 192.168.1.10
@property (nonatomic, assign) NSInteger smbPort;           // 445
@property (nonatomic, copy, nullable) NSString *share;     // 共享名
@property (nonatomic, copy, nullable) NSString *smbDomain; // 可空

// 通用
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, assign) BOOL readOnly;
@property (nonatomic, assign) BOOL autoMount;

+ (instancetype)mountFromDictionary:(NSDictionary *)d;
- (NSDictionary *)dictionaryRepresentation;
- (NSString *)kindString;

/// 本地根目录：Documents/Spark/Mounts/<displayName>
- (NSString *)localRootPath;

/// 描述文件路径（<root>/.sparkmount）
- (NSString *)descriptorPath;

@end

/// 挂载管理器
@interface SPMountManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<SPMount *> *mounts;

- (void)reload;
- (void)addMount:(SPMount *)mount password:(nullable NSString *)password;
- (void)removeMount:(SPMount *)mount;

/// Keychain 读写
- (void)setPassword:(NSString *)password forMount:(SPMount *)mount;
- (nullable NSString *)passwordForMount:(SPMount *)mount;

/// 列目录（异步，回调主线程）
- (void)listPath:(NSString *)remotePath
         ofMount:(SPMount *)mount
      completion:(void (^)(NSArray<SPMountEntry *> *_Nullable entries, NSError *_Nullable error))completion;

/// 下载文件到本地
- (void)download:(NSString *)remotePath
         ofMount:(SPMount *)mount
          toLocal:(NSString *)localPath
      completion:(void (^)(BOOL ok, NSError *_Nullable error))completion;

/// 上传本地文件到远端
- (void)uploadLocal:(NSString *)localPath
         toRemote:(NSString *)remotePath
            mount:(SPMount *)mount
         completion:(void (^)(BOOL ok, NSError *_Nullable error))completion;

/// 测试连通性
- (void)testMount:(SPMount *)mount
       completion:(void (^)(BOOL ok, NSString *detail))completion;

@end

NS_ASSUME_NONNULL_END
