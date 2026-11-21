//
//  SPNewProjectViewController.m
//  Spark —— 新建工程表单（对齐 dylix 的 StudioCreate）
//
#import "SPNewProjectViewController.h"
#import "SPStore.h"
#import "SPProject.h"
#import "SPTheme.h"
#import "SPMotion.h"
#import "SPCompat.h"

typedef NS_ENUM(NSInteger, SPNewProjectKind) {
    SPNewProjectKindObjectiveC = 0,   // 纯 Objective-C hook
    SPNewProjectKindLogos      = 1,   // Logos %hook 语法
    SPNewProjectKindDylib      = 2,   // 纯动态库，无过滤 plist
};

@interface SPNewProjectViewController () <UITextFieldDelegate>

@property (nonatomic) SPNewProjectKind kind;
@property (nonatomic, strong) NSMutableArray<UITextField *> *fields;
@property (nonatomic, strong) UISegmentedControl *kindControl;

@end

@implementation SPNewProjectViewController

#pragma mark - 字段定义

// 与 dylix 的 StudioCreate 一致：名称 / 包标识 / 作者 / 版本 / 目标 Bundle ID
- (NSArray<NSString *> *)fieldLabels {
    return @[@"项目名称", @"包标识", @"作者", @"版本", @"目标 Bundle ID"];
}

- (NSArray<NSString *> *)fieldDefaults {
    return @[@"HelloSpark", @"com.example.hellospark", @"Developer", @"1.0.0", @"com.apple.springboard"];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"新建工程";
    self.kind = SPNewProjectKindLogos;
    self.fields = [NSMutableArray array];

    // 模板选择
    self.kindControl = [[UISegmentedControl alloc] initWithItems:@[@"Objective-C", @"Logos", @"纯动态库"]];
    self.kindControl.selectedSegmentIndex = SPNewProjectKindLogos;
    [self.kindControl addTarget:self action:@selector(kindChanged:)
               forControlEvents:UIControlEventValueChanged];

    // 五个输入框
    NSArray *labels = [self fieldLabels];
    NSArray *defaults = [self fieldDefaults];
    for (NSUInteger i = 0; i < labels.count; i++) {
        UITextField *f = [[UITextField alloc] init];
        f.text = defaults[i];
        f.placeholder = labels[i];
        f.accessibilityLabel = labels[i];
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
        f.returnKeyType = (i + 1 == labels.count) ? UIReturnKeyDone : UIReturnKeyNext;
        f.delegate = self;
        f.tag = 1000 + (NSInteger)i;
        f.font = [UIFont systemFontOfSize:15];
        f.textColor = [SPTheme text];
        [self.fields addObject:f];
    }

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"创建"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(createTapped)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(cancelTapped)];

    self.tableView.backgroundColor = [SPTheme background];
}

- (void)kindChanged:(UISegmentedControl *)sc {
    self.kind = (SPNewProjectKind)sc.selectedSegmentIndex;
    // 纯动态库不需要过滤 plist 的目标，把最后一行说明改掉即可
    [self.tableView reloadData];
    [SPMotion hapticLight];
}

- (void)cancelTapped {
    if (self.onFinish) self.onFinish(nil);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 1 : (NSInteger)self.fields.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"选择项目模板" : @"项目与包信息";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        switch (self.kind) {
            case SPNewProjectKindObjectiveC:
                return @"生成 .m 源码，用 objc_msgSend 手写 hook，编译为 dylib。";
            case SPNewProjectKindLogos:
                return @"生成 .x 源码，用 Logos 的 %hook 语法，由内置预处理器展开。";
            case SPNewProjectKindDylib:
                return @"生成纯动态库：没有过滤 plist，需要宿主 App 自己加载。";
        }
        return nil;
    }
    return @"生成源码、过滤 plist、control 与 MobileCompiler.json。"
            "目标 Bundle ID 用于过滤 plist，纯动态库模板可忽略；"
            "构建架构与最低系统版本取「设置 → 编译默认值」，可在工程里再调整。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                    reuseIdentifier:nil];
    cell.backgroundColor = [SPTheme surface];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *content = nil;
    if (ip.section == 0) {
        self.kindControl.translatesAutoresizingMaskIntoConstraints = NO;
        content = self.kindControl;
    } else {
        UITextField *field = self.fields[ip.row];
        UILabel *caption = [[UILabel alloc] init];
        caption.text = [self fieldLabels][ip.row];
        caption.font = [UIFont systemFontOfSize:12];
        caption.textColor = [SPTheme textDim];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[caption, field]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        content = stack;
    }

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:SPSpaceM],
        [content.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-SPSpaceM],
        [content.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
        [content.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
    ]];
    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    NSInteger next = tf.tag - 1000 + 1;
    if (next < (NSInteger)self.fields.count) {
        [self.fields[next] becomeFirstResponder];
    } else {
        [tf resignFirstResponder];
        [self createTapped];
    }
    return YES;
}

#pragma mark - 创建

- (void)createTapped {
    [self.view endEditing:YES];

    NSString *name = [self.fields[0].text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *bundle = [self.fields[1].text stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *author = [self.fields[2].text stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *version = [self.fields[3].text stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *target = [self.fields[4].text stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (!name.length) return [self alert:@"请填写项目名称" message:@"英文名，会用作目录名与工程名。"];
    if (!bundle.length) return [self alert:@"请填写包标识" message:@"例如 com.example.mytweak。"];
    if (!version.length) version = @"1.0.0";
    if (!author.length) author = @"Developer";
    if (!target.length) target = @"com.apple.springboard";

    NSError *err = nil;
    NSString *path = [self createProjectWithName:name
                                          bundle:bundle
                                          author:author
                                         version:version
                                          target:target
                                            kind:self.kind
                                           error:&err];
    if (!path) {
        [self alert:@"创建失败" message:err.localizedDescription ?: @"同名工程可能已存在"];
        return;
    }

    [SPMotion hapticSuccess];
    if (self.onFinish) self.onFinish(path);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 模板生成

- (NSString *)createProjectWithName:(NSString *)name
                             bundle:(NSString *)bundle
                             author:(NSString *)author
                            version:(NSString *)version
                             target:(NSString *)target
                               kind:(SPNewProjectKind)kind
                              error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [SPStore shared].projectsDirectory;
    NSString *path = [root stringByAppendingPathComponent:name];

    if ([fm fileExistsAtPath:path]) {
        if (error) *error = SPError(SPErrorCodeIO, @"同名工程已存在");
        return nil;
    }
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error])
        return nil;

    BOOL isDylib = (kind == SPNewProjectKindDylib);
    BOOL isLogos = (kind == SPNewProjectKindLogos);

    // ── Makefile ──
    NSString *files = isLogos ? @"Tweak.x" : (isDylib ? @"Tweak.m" : @"Tweak.m");
    NSMutableString *mk = [NSMutableString string];
    [mk appendString:@"TARGET = iphone:clang:latest:15.0\n"];
    [mk appendString:@"ARCHS = arm64 arm64e\n"];
    if (!isDylib) {
        [mk appendFormat:@"INSTALL_TARGET_PROCESSES = %@\n", target];
    }
    [mk appendString:@"\ninclude $(THEOS)/makefiles/common.mk\n\n"];
    [mk appendFormat:@"TWEAK_NAME = %@\n\n", name];
    [mk appendFormat:@"%@_FILES = %@\n", name, files];
    [mk appendFormat:@"%@_CFLAGS = -fobjc-arc\n\n", name];
    [mk appendString:@"include $(THEOS_MAKE_PATH)/tweak.mk\n"];
    [mk writeToFile:[path stringByAppendingPathComponent:@"Makefile"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    // ── control（含作者与版本，与 dylix 一致）──
    NSString *control = [NSString stringWithFormat:
        @"Package: %@\nName: %@\nVersion: %@\nArchitecture: iphoneos-arm64\n"
         "Description: 由 Spark 创建\nMaintainer: %@\nAuthor: %@\nSection: Tweaks\n",
        bundle, name, version, author, author];
    [control writeToFile:[path stringByAppendingPathComponent:@"control"]
               atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    // ── 过滤 plist（纯动态库不生成）──
    if (!isDylib) {
        NSString *plist = [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
             "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
             "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
             "<plist version=\"1.0\">\n<dict>\n"
             "\t<key>Filter</key>\n\t<dict>\n"
             "\t\t<key>Bundles</key>\n\t\t<array>\n\t\t\t<string>%@</string>\n\t\t</array>\n"
             "\t</dict>\n</dict>\n</plist>\n", target];
        [plist writeToFile:[path stringByAppendingPathComponent:
                            [name stringByAppendingString:@".plist"]]
                 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }

    // ── 源码 ──
    if (isLogos) {
        [@"// Spark 生成的 Logos tweak\n%hook SpringBoard\n\n"
          "- (void)applicationDidFinishLaunching:(id)application {\n"
          "    %orig;\n    NSLog(@\"[SPARK] loaded\");\n}\n\n%end\n"
         writeToFile:[path stringByAppendingPathComponent:@"Tweak.x"]
         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    } else if (isDylib) {
        [@"// Spark 生成的纯动态库：没有过滤 plist，需要宿主自行加载\n"
          "#import <Foundation/Foundation.h>\n\n"
          "__attribute__((constructor)) static void SparkDylibInit(void) {\n"
          "    NSLog(@\"[SPARK] dylib loaded\");\n}\n"
         writeToFile:[path stringByAppendingPathComponent:@"Tweak.m"]
         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    } else {
        [@"// Spark 生成的 Objective-C tweak\n"
          "#import <Foundation/Foundation.h>\n"
          "#import <objc/runtime.h>\n\n"
          "static IMP SPOrig_applicationDidFinishLaunching(id self, SEL _cmd, id app) {\n"
          "    return NULL;\n}\n\n"
          "__attribute__((constructor)) static void SparkHookInit(void) {\n"
          "    Class cls = objc_getClass(\"SpringBoard\");\n"
          "    SEL sel = sel_registerName(\"applicationDidFinishLaunching:\");\n"
          "    Method m = class_getInstanceMethod(cls, sel);\n"
          "    if (m) SPOrig_applicationDidFinishLaunching = method_getImplementation(m);\n"
          "    NSLog(@\"[SPARK] hooked\");\n}\n"
         writeToFile:[path stringByAppendingPathComponent:@"Tweak.m"]
         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }

    // ── MobileCompiler.json（dylix 也生成这个）──
    [self writeCompilerManifest:path name:name bundle:bundle isDylib:isDylib];

    // ── 目录与忽略文件 ──
    [fm createDirectoryAtPath:[path stringByAppendingPathComponent:@"layout/DEBIAN"]
  withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"*.deb\npackages/\n.theos/\n_build/\n*.dSYM/\nobj/\n.sparkbak/\n"
     writeToFile:[path stringByAppendingPathComponent:@".gitignore"]
        atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    return path;
}

- (void)writeCompilerManifest:(NSString *)path
                         name:(NSString *)name
                       bundle:(NSString *)bundle
                      isDylib:(BOOL)isDylib {
    // 由运行时（SPRuntimeLayout / SPToolchain）读取的是
    // 「工程名 + 产物名 + 包标识」，不涉及工具链路径 —— 
    // 工具链位置仍由 App 内的探测决定，这里不写死任何运行时路径。
    NSDictionary *manifest = @{
        @"schema": @1,
        @"name": name,
        @"package": bundle,
        @"product": [name stringByAppendingString:@".dylib"],
        @"filters": isDylib ? @[] : @[[name stringByAppendingString:@".plist"]],
        @"sources": @[isDylib ? @"Tweak.m" : @"Tweak.m"],
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:NULL];
    if (data) {
        [data writeToFile:[path stringByAppendingPathComponent:@"MobileCompiler.json"] atomically:YES];
    }
}

@end