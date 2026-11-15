# 示例项目

这里放几个可以直接被 ReinBuild 打开、编译的最小工程，用来做回归测试。

| 目录 | 类型 | 用途 |
|---|---|---|
| `DemoTweak/` | Tweak | 最小可编译 tweak（hook SpringBoard），验证日志/诊断链路 |
| `DemoApp/` | Application | 最小 iOS App，验证 application.mk 分支 |
| `BrokenTweak/` | Tweak（故意写错） | 验证失败诊断能不能给出对的中文建议 |

用法：App 里「项目 → + → 从磁盘选择目录」，选到示例目录即可。
