#!/usr/bin/env python3
"""把工程改成「你的签名环境」：设置 Bundle 前缀、Team ID、是否启用 App Group。

为什么不直接在 shell 里 sed：bundle id 会被反复改写（冲突时要换后缀），
需要幂等；而且三个 target 的后缀不同（.app / .app.DawnusWidget / .app.tests）。
逐行解析比正则安全得多——正则里 `com\\.dawnus\\.` 会吃掉分隔点，导致
`com.dawnus.app` 这种最短形式匹配不上。

用法:
    python3 scripts/configure.py --prefix com.dawnus.a1b2c3 --team A1B2C3D4E5 [--app-group]
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "project.yml")
SHARED_STORE = os.path.join(ROOT, "Dawnus", "Store", "SharedStore.swift")

# 三个 target 各自的固定后缀（顺序无关，解析时以 "app" 段为锚点）
SUFFIXES = (".app.DawnusWidget", ".app.tests", ".app")


def rewrite_bundle_id(text: str, prefix: str) -> str:
    """把所有 com.dawnus.* 开头的 bundle id 改成 prefix + 原后缀。幂等。"""
    out = []
    changed = 0
    for line in text.split("\n"):
        marker = "PRODUCT_BUNDLE_IDENTIFIER:"
        if marker in line and "com.dawnus" in line:
            before, _, rest = line.partition(marker)
            value = rest.strip()
            # value 形如 com.dawnus.app / com.dawnus.a1b2c3.app.DawnusWidget
            parts = value.split(".")
            # 以 "app" 那一段为锚点，取它及其之后的部分作为后缀
            if "app" in parts:
                tail = "." + ".".join(parts[parts.index("app"):])
            else:
                tail = SUFFIXES[-1]
            line = f"{before}{marker} {prefix}{tail}"
            changed += 1
        out.append(line)
    if changed == 0:
        print("  ! 警告：没找到任何 PRODUCT_BUNDLE_IDENTIFIER，project.yml 结构可能变了",
              file=sys.stderr)
    return "\n".join(out), changed


def set_team(text: str, team: str) -> str:
    return re.sub(r'DEVELOPMENT_TEAM: "[^"]*"', f'DEVELOPMENT_TEAM: "{team}"', text)


def set_app_group_id(group_id: str) -> None:
    """同步 SharedStore 里的 App Group 标识。"""
    s = open(SHARED_STORE, encoding="utf-8").read()
    s = re.sub(r'static let appGroupID = "[^"]*"',
               f'static let appGroupID = "{group_id}"', s)
    open(SHARED_STORE, "w", encoding="utf-8").write(s)


def toggle_app_group(enable: bool, group_id: str) -> None:
    """切换 entitlements：默认那份不含 App Group（免费账号可签），带后缀那份含。

    注意 group_id 必须和 SharedStore 里的一致，否则 entitlement 声明的容器
    与代码访问的容器不是同一个，共享会静默失效。
    """
    pairs = (
        (os.path.join(ROOT, "Dawnus", "Dawnus.withAppGroup.entitlements"),
         os.path.join(ROOT, "Dawnus", "Dawnus.entitlements")),
        (os.path.join(ROOT, "DawnusWidget", "DawnusWidget.withAppGroup.entitlements"),
         os.path.join(ROOT, "DawnusWidget", "DawnusWidget.entitlements")),
    )
    for src, dst in pairs:
        if not os.path.exists(src):
            print(f"  ! 缺少 {os.path.basename(src)}，跳过", file=sys.stderr)
            continue
        if enable:
            content = open(src, encoding="utf-8").read()
            content = re.sub(r'group\.com\.dawnus[.A-Za-z0-9_-]*\.shared', group_id, content)
            open(dst, "w", encoding="utf-8").write(content)
            print(f"  已启用 App Group: {os.path.basename(dst)} → {group_id}")
        else:
            open(dst, "w", encoding="utf-8").write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0">\n'
                '<dict>\n'
                '<!-- 未启用 App Group：免费个人 Apple ID 无法签发该 capability。\n'
                '     代码已降级到进程内 UserDefaults（见 Store/SharedStore.swift）。 -->\n'
                '</dict>\n'
                '</plist>\n')
            print(f"  已关闭 App Group: {os.path.basename(dst)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True, help="Bundle id 前缀，如 com.dawnus.a1b2c3")
    ap.add_argument("--team", default=None, help="10 位 Team ID")
    ap.add_argument("--app-group", action="store_true", help="启用 App Group 跨进程共享")
    args = ap.parse_args()

    text = open(PROJECT, encoding="utf-8").read()

    text, n = rewrite_bundle_id(text, args.prefix)
    print(f"  Bundle id 已更新（{n} 处）→ {args.prefix}.*")

    if args.team:
        text = set_team(text, args.team)
        print(f"  Team ID 已写入 → {args.team}")

    open(PROJECT, "w", encoding="utf-8").write(text)

    group_id = f"group.{args.prefix}.shared"
    toggle_app_group(args.app_group, group_id)
    set_app_group_id(group_id)

    return 0


if __name__ == "__main__":
    sys.exit(main())
