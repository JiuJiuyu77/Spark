//
//  SPHelp.m
//

#import "SPHelp.h"

@implementation SPHelpArticle
@end

@implementation SPHelp

+ (SPHelpArticle *)article:(NSString *)title
                    summary:(NSString *)summary
                     symbol:(NSString *)symbol
                   category:(NSString *)category
                       body:(NSString *)body {
    SPHelpArticle *a = [SPHelpArticle new];
    a.title = title;
    a.summary = summary;
    a.symbol = symbol;
    a.category = category;
    a.body = body;
    return a;
}

+ (NSArray<SPHelpArticle *> *)articles {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            // ---------------- 入门 ----------------
            [self article:@"第一次使用" summary:@"三步编出第一个插件"
                   symbol:@"hand.wave" category:@"入门" body:
@"## 三步开始\n\n"
 "**1. 确认工具链**\n\n"
 "打开「设置 → 工具链」，应看到「内置工具链 · 已就绪」。\n"
 "若显示未展开，点「展开工具链」等几十秒。\n\n"
 "**2. 建一个工程**\n\n"
 "「项目」页右上角 ＋ → 新建 Tweak 工程。\n"
 "只需填包名（如 com.你的名字.demo），其余默认即可。\n\n"
 "**3. 编译**\n\n"
 "进入工程 → 点「开始编译」。\n"
 "成功后会看到 `packages/xxx.deb`，点它可以安装或分享。\n\n"
 "> 手机上编一个简单插件的耗时通常在 10~30 秒。"],

            [self article:@"安装 SDK" summary:@"编译需要 iPhoneOS SDK"
                   symbol:@"shippingbox" category:@"入门" body:
@"## SDK 从哪来\n\n"
 "**Workbench 已内置 SDK**：iPhoneOS 16.5（完整，开箱即用）。\n"
 "17.0 / 26.5 可在「工具 → 工具链 → 默认 SDK」按需下载，\n"
 "下载后自动可选用，不需要额外准备。\n\n"
 "随 App 一起装好，不需要任何额外准备，也不依赖其它 App。\n\n"
 "如果内置的缺失或不完整，可以自己补：\n\n"
 "**方法一：从 Xcode 拷**\n\n"
 "在 `iPhoneOS.platform/Developer/SDKs/` 里取出 `.sdk` 目录，\n"
 "压成 zip 传到手机。\n\n"
 "**方法二：导入**\n\n"
 "拿到后：设置 → 工具链 → 导入 SDK 压缩包。"],

            [self article:@"导入已有工程" summary:@"从文件 App 或收件箱导入"
                   symbol:@"tray.and.arrow.down" category:@"入门" body:
@"## 三种导入方式\n\n"
 "**1. 从「文件」App 导入**\n\n"
 "项目页 ＋ → 「从「文件」导入…」\n"
 "支持 zip / ipa / deb / tar.gz / tar.xz，会自动解压并找到工程根。\n\n"
 "**2. 其他 App 分享过来**\n\n"
 "在任何 App 里点分享 → 选 Workbench，文件会进「收件箱」。\n\n"
 "**3. 从收件箱导入**\n\n"
 "我的 → 收件箱 → 选文件 → 「导入为项目」。\n\n"
 "> 判断工程根的依据：目录里有 `Makefile`。"],

            // ---------------- 编译 ----------------
            [self article:@"编译选项说明" summary:@"架构 / 包格式 / 优化 / 混淆怎么选"
                   symbol:@"slider.horizontal.3" category:@"编译" body:
@"## 架构（ARCHS）\n\n"
 "· `arm64` —— 大多数设备，最稳\n"
 "· `arm64e` —— A12 及以上，指针认证\n"
 "· `arm64 arm64e` —— 两者都带，包更大\n\n"
 "**不确定就选 arm64。**\n\n"
 "## 包格式\n\n"
 "· **rootful** —— 传统越狱（/usr/lib）\n"
 "· **rootless** —— Dopamine / palera1n 无根越狱（/var/jb）\n"
 "· **roothide** —— RootHide 方案\n"
 "· **.app / .tipa** —— 只要 App 不要 deb\n\n"
 "装在哪台机器上就用哪种，选错会装不上。\n\n"
 "## 优化等级\n\n"
 "· `-O0` 调试，方便看崩溃栈\n"
 "· `-O2` **发布推荐**\n"
 "· `-Os` / `-Oz` 体积优先\n\n"
 "## 混淆强度\n\n"
 "· 轻度：加间接跳转 + 字符串加密，体积影响最小\n"
 "· 均衡：再加间接调用，日常够用\n"
 "· 强力：7 个 pass 全开，可能影响性能\n\n"
 "> 混淆只能增加逆向成本，不能防住决心足够的人。"],

            [self article:@"OLLVM 混淆原理" summary:@"五个（现在七个）pass 各自做什么"
                   symbol:@"lock.shield" category:@"编译" body:
@"## 各 pass 的作用\n\n"
 "**indbr（间接跳转）**\n"
 "把 `br label` 改成从跳转表取地址，打乱控制流图。\n\n"
 "**icall（间接调用）**\n"
 "函数调用改成查表调用，静态分析看不到目标。\n\n"
 "**indgv（间接全局变量）**\n"
 "全局变量访问改走指针表。\n\n"
 "**cse（字符串加密）**\n"
 "字符串常量在运行时解密，`strings` 看不到原文。\n\n"
 "**fla（控制流平坦化）**\n"
 "把基本块塞进一个 switch 状态机，反编译后是一团乱麻。\n"
 "（旧版叫 cff）\n\n"
 "**cie / cfe** —— 间接调用与控制流增强，LLVM 23 新增。\n\n"
 "## 建议\n\n"
 "先不混淆编一版确认功能正常，再开混淆对比体积和性能。"],

            // ---------------- 注入 ----------------
            [self article:@"巨魔注入是什么" summary:@"把 dylib 塞进别人的 App"
                   symbol:@"syringe" category:@"注入" body:
@"## 原理\n\n"
 "iOS 上想改别的 App，只有一条路：**让它启动时加载你的代码**。\n\n"
 "做法是修改目标 App 的主二进制，加一条 `LC_LOAD_DYLIB` 命令，\n"
 "指向你的 dylib。App 启动时 dyld 就会加载它。\n\n"
 "## Workbench 的流程\n\n"
 "1. 备份目标 App 为 `.sparkbak`\n"
 "2. 把 dylib 复制进 App\n"
 "3. 准备 CydiaSubstrate（`%hook` 的运行时）\n"
 "4. `insert_dylib` 插入加载命令\n"
 "5. `ldid` 重新签名\n"
 "6. 重启目标 App\n\n"
 "## 风险\n\n"
 "· 改坏了 App 打不开 —— 用「卸载注入」恢复 `.sparkbak`\n"
 "· 某些 App 有完整性校验，注入后会闪退\n"
 "· 系统 App 不建议注入"],

            [self article:@"为什么注入后闪退" summary:@"CoreTrust 与签名问题"
                   symbol:@"exclamationmark.triangle" category:@"注入" body:
@"## 最常见的原因\n\n"
 "**没有 ct_bypass**\n\n"
 "TrollStore 安装 App 时依赖 CoreTrust 漏洞接受伪签名。\n"
 "你注入后的 App 也需要同样处理，否则系统拒绝加载。\n\n"
 "注入面板里打开「CoreTrust 绕过」选项，\n"
 "并确保 `ct_bypass` 在工具链 bin 目录里。\n\n"
 "**没有 CydiaSubstrate**\n\n"
 "`%hook` 依赖 Substrate 运行时。Workbench 会自动准备，\n"
 "但如果你只拷了 dylib 没带 framework，就会闪退。\n\n"
 "**App 有反注入保护**\n\n"
 "部分银行、社交类 App 会检测 `LC_LOAD_DYLIB`。这种情况无解。"],

            // ---------------- 排错 ----------------
            [self article:@"ipa 装不上怎么办" summary:@"用签名审计定位"
                   symbol:@"checkmark.shield" category:@"排错" body:
@"## 先跑签名审计\n\n"
 "工具 → 签名审计 → 选你的 ipa。\n\n"
 "它会逐项检查：\n\n"
 "· 文件是否被截断（下载不完整）\n"
 "· 是否缺少代码签名\n"
 "· 签名与文件内容是否一致（逐页 SHA-256）\n"
 "· 是否有符号链接（ldid 不认）\n"
 "· 是否有空壳 bundle（Info.plist 指向不存在的二进制）\n"
 "· 是否有 ar 静态库（ldid 处理不了）\n\n"
 "## 常见报错的含义\n\n"
 "**`ldid: Unknown header magic`**\n"
 "ldid 读到非 Mach-O 的文件。多半是空壳 bundle 或 ar 静态库。\n\n"
 "**`Invalid update: invalid number of items`**\n"
 "这是 App 自己的 bug，不是安装包的问题。"],

            [self article:@"编译失败怎么查" summary:@"从日志判断问题"
                   symbol:@"text.magnifyingglass" category:@"排错" body:
@"## 先看日志里的 `[!]` 行\n\n"
 "Workbench 会在关键步骤打 `[ok]` / `[!]`，`[!]` 就是问题点。\n\n"
 "## 常见错误\n\n"
 "**找不到头文件**\n"
 "`fatal error: 'UIKit/UIKit.h' file not found`\n"
 "→ SDK 没装好，或 TARGET 里的版本号比 SDK 还新\n\n"
 "**找不到符号**\n"
 "`Undefined symbols: _OBJC_CLASS_$_XXX`\n"
 "→ Makefile 里没写 `XXX_FRAMEWORKS = XXX`\n\n"
 "**Logos 报错**\n"
 "`%hook` 后面类名拼错，或者忘了 `%end`\n\n"
 "**权限不够**\n"
 "`Permission denied`\n"
 "→ 工具链没解包完整，设置里点「重装工具链」"],

            // ---------------- 进阶 ----------------
            [self article:@"远程编译" summary:@"用另一台设备或云端编译"
                   symbol:@"network" category:@"进阶" body:
@"## 三种构建目标\n\n"
 "**本机** —— 直接在这台手机上编\n\n"
 "**远程 SSH** —— 编到另一台设备\n"
 "填 host / user / port，以及密钥路径。\n"
 "适合本地性能不够（大工程）或想要 arm64e。\n\n"
 "**GitHub CI** —— 推到 GitHub 让它编\n"
 "填 owner/repo 和 token。好处是不占手机资源，\n"
 "而且 CI 上编出来的包签名干净。\n\n"
 "## 局域网工作台\n\n"
 "工具 → 局域网工作台 → 开启。\n"
 "电脑浏览器输入显示的地址 + 访问码，就能在线改代码和编译。"],

            [self article:@"Git 集成" summary:@"编译前自动存快照"
                   symbol:@"arrow.triangle.branch" category:@"进阶" body:
@"## 为什么需要\n\n"
 "改代码改崩了想回退，没有 Git 就只能靠记忆。\n\n"
 "## Workbench 做什么\n\n"
 "设置里「编译前自动快照」默认开启。\n"
 "每次编译前，若工程是 git 仓库且有未提交改动，\n"
 "会自动 `git add -A && git commit`。\n\n"
 "这样你随时能回到「上一次能编过的状态」。\n\n"
 "## 手动操作\n\n"
 "工程页 → Git 版本管理：\n"
 "· 看改动列表\n"
 "· 单文件暂存\n"
 "· 提交\n"
 "· 查看历史\n"
 "· 推送到 GitHub（token 存在内存里，不落盘）"],

            [self article:@"产物命名模板" summary:@"自定义 deb / tipa 文件名"
                   symbol:@"textformat" category:@"进阶" body:
@"## 可用占位符\n\n"
 "`{name}` 产品名 · `{version}` 版本 · `{build}` 构建号\n"
 "`{arch}` 架构 · `{packageArch}` 包架构 · `{scheme}` 有根/无根\n"
 "`{bundleId}` 包名 · `{date}` 日期 · `{time}` 时间\n\n"
 "## 常用组合\n\n"
 "```\n"
 "{name}_{version}_{packageArch}      ← Theos 默认\n"
 "{bundleId}_{version}_{arch}         ← 更精确\n"
 "{name}-{version}-{date}             ← 带日期，便于对比\n"
 "```\n\n"
 "> 模板里必须有 `{name}`，否则多个产物会互相覆盖。"],
        ];
    });
    return list;
}

+ (NSArray<NSDictionary *> *)groupedArticles {
    NSMutableArray *order = [NSMutableArray array];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (SPHelpArticle *a in [self articles]) {
        if (!map[a.category]) {
            map[a.category] = [NSMutableArray array];
            [order addObject:a.category];
        }
        [map[a.category] addObject:a];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *cat in order) {
        [out addObject:@{@"category": cat, @"items": map[cat]}];
    }
    return out;
}

+ (NSArray<SPHelpArticle *> *)search:(NSString *)keyword {
    if (!keyword.length) return [self articles];
    NSMutableArray *out = [NSMutableArray array];
    for (SPHelpArticle *a in [self articles]) {
        BOOL hit = [a.title localizedCaseInsensitiveContainsString:keyword]
                || [a.summary localizedCaseInsensitiveContainsString:keyword]
                || [a.body localizedCaseInsensitiveContainsString:keyword]
                || [a.category localizedCaseInsensitiveContainsString:keyword];
        if (hit) [out addObject:a];
    }
    return out;
}

@end
