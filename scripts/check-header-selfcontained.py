#!/usr/bin/env python3
"""检查每个 .h 是否「自包含」：用到的系统/自定义类型都有对应的 import。

典型翻车：头文件里写了 UIColor * 却只 import 了 Foundation —— 编译到
"expected a type"。真机上不会立刻发现，CI 上要等十分钟。
"""
import glob
import os
import re
import sys

SRC = 'Native/ObjC'

UIKIT_TYPES = [
    'UIColor', 'UIFont', 'UIView', 'UIImage', 'UIImageView', 'UILabel', 'UIButton',
    'UIViewController', 'UITableView', 'UITableViewCell', 'UITableViewDataSource',
    'UITableViewDelegate', 'UISwitch', 'UIApplication', 'UIWindow', 'UIScrollView',
    'UITextView', 'UITextViewDelegate', 'UIScrollViewDelegate', 'UICollectionView',
    'UIDocumentPickerViewController', 'UIDocumentPickerDelegate', 'UIAlertController',
    'UIActivityViewController', 'UIVisualEffectView', 'UIBlurEffect', 'UIProgressView',
    'UISegmentedControl', 'UIStackView', 'UIBarButtonItem', 'UIButtonConfiguration',
    'UISearchController', 'UISearchResultsUpdating', 'UITraitCollection', 'UIMenu',
    'UIAction', 'UIContextMenuConfiguration', 'UIMenuElement', 'UIImpactFeedbackGenerator',
    'UINotificationFeedbackGenerator', 'UIEdgeInsets', 'CGRect', 'CGSize', 'CGPoint',
    'CGFloat', 'UILayoutPriority', 'UIFontTextStyle', 'NSDirectionalEdgeInsets',
    'UIControlContentHorizontalAlignment', 'UILayoutConstraintAxis',
    'UIControlEvents', 'UIScrollViewIndicatorStyle', 'UIKeyboardAppearance',
    'UIBarStyle', 'UINavigationItemLargeTitleDisplayMode', 'UIKeyboardType',
]


def check_header(path: str):
    raw = open(path, encoding='utf-8').read()
    # 去掉注释再判断（注释里提到类名不该算依赖）
    text = re.sub(r'//[^\n]*', '', raw)
    text = re.sub(r'/\*[\s\S]*?\*/', '', text)
    problems = []
    if '#import <UIKit/UIKit.h>' not in text:
        for t in UIKIT_TYPES:
            if re.search(r'\b' + re.escape(t) + r'\b', text):
                problems.append(f'{os.path.basename(path)}: 用了 {t} 但没有 #import <UIKit/UIKit.h>')
                break

    # 自定义类型：SPFoo * 但没有 import SPFoo.h（且不是自己声明的）
    own = set(re.findall(r'@(?:interface|class|protocol)\s+(\w+)', text))
    imported = set(re.findall(r'#import\s+"(\w+\.h)"', text))
    declared = {}
    for h in glob.glob(os.path.join(SRC, '*.h')):
        for name in re.findall(r'@interface\s+(\w+)', open(h, encoding='utf-8').read()):
            declared.setdefault(name, set()).add(os.path.basename(h))

    # 展开一层间接导入
    visible = set()
    for i in imported:
        p = os.path.join(SRC, i)
        if os.path.exists(p):
            visible |= set(re.findall(r'@interface\s+(\w+)', open(p, encoding='utf-8').read()))
            visible |= set(re.findall(r'@class\s+(\w+)', open(p, encoding='utf-8').read()))

    for used in set(re.findall(r'\b(SP[A-Z]\w+)\b', text)):
        if used in own or used in visible or used not in declared:
            continue
        problems.append(f'{os.path.basename(path)}: 用了 {used} 但没有 #import '
                        f'{"/".join(sorted(declared[used]))}')
    return problems


def main() -> int:
    files = sorted(glob.glob(os.path.join(SRC, '*.h')))
    problems = []
    for f in files:
        problems.extend(check_header(f))
    if problems:
        print(f'发现 {len(problems)} 个头文件问题：')
        for p in problems:
            print('  ' + p)
        return 1
    print(f'头文件自包含检查通过（{len(files)} 个 .h）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
