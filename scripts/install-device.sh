#!/usr/bin/env bash
#
# 拂晓 DAWNUS —— 一键真机部署
#
# 用法:
#   ./scripts/install-device.sh                    # 自动找设备、自动找签名团队
#   ./scripts/install-device.sh A1B2C3D4E5         # 指定 Team ID
#   ./scripts/install-device.sh --app-group        # 付费账号：启用 App Group 跨进程共享
#   ./scripts/install-device.sh --bundle-prefix com.yourname.dawnus
#
# 它会依次做：找设备 → 查 iOS 版本 → 找签名身份 → 生成唯一 bundle id
#            → xcodegen → xcodebuild(真机) → devicectl install
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'

info() { printf '%s\n' "${C_CYAN}▸${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GREEN}✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}!${C_RESET} $*"; }
die()  { printf '%s\n' "${C_RED}✗ $*${C_RESET}" >&2; exit 1; }
step() { printf '\n%s\n' "${C_BOLD}$*${C_RESET}"; }

# ---------------------------------------------------------------- 参数

TEAM_ID=""
ENABLE_APP_GROUP=0
BUNDLE_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-group)      ENABLE_APP_GROUP=1; shift ;;
    --bundle-prefix)  BUNDLE_PREFIX="${2:-}"; [[ -n "$BUNDLE_PREFIX" ]] || die "--bundle-prefix 需要一个值"; shift 2 ;;
    -h|--help)        sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)                TEAM_ID="$1"; shift ;;
  esac
done

# ---------------------------------------------------------------- 1. 工具依赖

step "1/7  检查工具链"

command -v xcodegen  >/dev/null 2>&1 || die "缺少 xcodegen，先装：brew install xcodegen"
command -v xcodebuild >/dev/null 2>&1 || die "缺少 Xcode 命令行工具"
command -v python3   >/dev/null 2>&1 || die "缺少 python3（用于解析设备列表）"
XCODE=$(xcode-select -p 2>/dev/null || true)
[[ -n "$XCODE" ]] || die "未设置 Xcode 路径，先跑：sudo xcode-select -s /Applications/Xcode.app"
ok "Xcode: $XCODE"

# ---------------------------------------------------------------- 2. 找设备

step "2/7  查找已连接的 iPhone"

DEV_JSON="$(mktemp -t dawnus-devices).json"
PICK="$(mktemp -t dawnus-pick).py"
cat >"$PICK" <<'PY'
# 从 devicectl 的 JSON 里挑出第一台 iPhone。
# devicectl 各版本字段名不完全一致，所以递归搜，而不是硬编码层级。
import json, sys

def walk(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == 'udid' and isinstance(v, str) and len(v) >= 24:
                out['udid'] = out.get('udid') or v
            elif k in ('name', 'deviceName') and isinstance(v, str) and not out.get('name'):
                out['name'] = v
            elif k in ('osVersionNumber', 'osVersion') and isinstance(v, str):
                out['os'] = out.get('os') or v
            else:
                walk(v, out)
    elif isinstance(node, list):
        for item in node:
            walk(item, out)

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    print('||'); sys.exit(0)

out = {}
walk(data, out)
print('%s|%s|%s' % (out.get('udid', ''), out.get('name', 'iPhone'), out.get('os', '0.0')))
PY

xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1 || true
IFS='|' read -r DEV_UDID DEV_NAME DEV_OS < <(python3 "$PICK" "$DEV_JSON")
DEV_OS="${DEV_OS:-0.0}"

if [[ -z "$DEV_UDID" ]]; then
  warn "没有检测到已配对的设备。"
  cat <<'GUIDE'
  请按顺序确认（只需做一次）：

    iPhone 上：
      1. 设置 → 通用 → 软件更新，升到 iOS 26.0 或更高（AlarmKit 的硬要求）
      2. 设置 → 隐私与安全性 → 开发者模式 → 打开（会要求重启）
      3. 用数据线连上 Mac，解锁手机并点「信任此电脑」

    Mac 上：
      4. 打开 Xcode → Window → Devices and Simulators，左侧应能看到你的 iPhone
      5. 打开 Xcode → Settings → Accounts，点 + 登录你的 Apple ID
         （免费 Apple ID 即可；付费开发者账号额外支持 App Group）

  完成后重跑本脚本。想走无线调试：在 Devices and Simulators 里勾上
  「Connect via network」，之后拔线也能装。
GUIDE
  exit 1
fi

ok "设备: $DEV_NAME  (iOS $DEV_OS)  $DEV_UDID"

# AlarmKit 需要 iOS 26+
OS_MAJOR="${DEV_OS%%.*}"
if [[ "$OS_MAJOR" -lt 26 ]]; then
  die "这台设备是 iOS $DEV_OS，但 AlarmKit 需要 iOS 26.0 以上。
       请在 iPhone 上升级系统，或改用模拟器验证（闹钟不会真响）。"
fi

# ---------------------------------------------------------------- 3. 签名身份

step "3/7  查找签名团队"

if [[ -z "$TEAM_ID" ]]; then
  # 从钥匙串里的 Apple Development 证书反查 Team ID。
  # subject 有两种常见排版（/OU=XXXX 与 OU = XXXX），两种都要能认。
  CERT_SUBJ=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null || true)

  TEAM_ID=$(printf '%s' "$CERT_SUBJ" \
    | grep -oE 'OU[ ]?=[ ]?[A-Z0-9]{10}' | head -1 | grep -oE '[A-Z0-9]{10}' || true)

  if [[ -z "$TEAM_ID" ]]; then
    # 有些证书没有 OU，退回从 CN 的括号里取：CN=Apple Development: 名字 (TEAMID)
    TEAM_ID=$(printf '%s' "$CERT_SUBJ" \
      | grep -oE '\([A-Z0-9]{10}\)' | head -1 | tr -d '()' || true)
  fi
fi

if [[ -z "$TEAM_ID" ]]; then
  warn "本机还没有任何签名证书。"
  cat <<'GUIDE'
  需要先让 Xcode 生成签名身份：

    1. 打开 Xcode → Settings → Accounts → 左下角 + → 登录 Apple ID
    2. 登录后选中你的账号，Xcode 会自动创建「Personal Team」证书
    3. 重新跑本脚本

  想知道 Team ID 是什么：developer.apple.com → Membership → Team ID，
  或从 Xcode 的 Signing 面板里看括号中那串 10 位字符。
GUIDE
  exit 1
fi
ok "Team ID: $TEAM_ID"

# ---------------------------------------------------------------- 4. bundle id

step "4/7  准备 Bundle Identifier"

if [[ -z "$BUNDLE_PREFIX" ]]; then
  # com.dawnus.app 这种通用名字很可能已被别人的账号占用。
  # 免费账号下 App ID 冲突会直接导致签名失败，所以默认加一段本机相关的后缀。
  SUFFIX=$(printf '%s' "$(whoami)$TEAM_ID" | shasum -a 256 | cut -c1-6)
  BUNDLE_PREFIX="com.dawnus.$SUFFIX"
  info "自动生成唯一前缀: $BUNDLE_PREFIX（避免 App ID 与他人冲突）"
else
  info "使用指定前缀: $BUNDLE_PREFIX"
fi

CFG_ARGS=(--prefix "$BUNDLE_PREFIX" --team "$TEAM_ID")
[[ "$ENABLE_APP_GROUP" == "1" ]] && CFG_ARGS+=(--app-group)
python3 "$ROOT/scripts/configure.py" "${CFG_ARGS[@]}"

APP_GROUP_ID="group.$BUNDLE_PREFIX.shared"
[[ "$ENABLE_APP_GROUP" == "1" ]] \
  && ok "已启用 App Group: $APP_GROUP_ID" \
  || warn "未启用 App Group（免费 Apple ID 的硬限制）。已自动降级到进程内存储，功能不受影响。"

ok "主 App:   $BUNDLE_PREFIX.app"
ok "实时活动: $BUNDLE_PREFIX.app.DawnusWidget"

# ---------------------------------------------------------------- 5. 生成工程

step "5/7  生成 Xcode 工程"
USER="$(whoami)" LOGNAME="$(whoami)" xcodegen generate --quiet 2>&1 | tail -3 || true
[[ -d Dawnus.xcodeproj ]] || die "工程生成失败"
ok "Dawnus.xcodeproj 已就绪"

# ---------------------------------------------------------------- 6. 编译

step "6/7  为真机编译（首次会联网申请签名，可能要几十秒）"

BUILD_LOG=$(mktemp -t dawnus-build).log
if ! xcodebuild \
      -project Dawnus.xcodeproj \
      -scheme Dawnus \
      -destination "id=$DEV_UDID" \
      -allowProvisioningUpdates \
      -derivedDataPath build/DerivedData \
      build >"$BUILD_LOG" 2>&1; then

  # App ID 被别人占了 → 换随机后缀重试一次
  if grep -qE "not available|couldn'?t be registered|An App ID with Identifier" "$BUILD_LOG"; then
    warn "Bundle id $BUNDLE_PREFIX.app 已被占用，换一个重试…"
    BUNDLE_PREFIX="com.dawnus.$(head -c 32 /dev/urandom | shasum -a 256 | cut -c1-6)"
    CFG_ARGS=(--prefix "$BUNDLE_PREFIX" --team "$TEAM_ID")
    [[ "$ENABLE_APP_GROUP" == "1" ]] && CFG_ARGS+=(--app-group)
    python3 "$ROOT/scripts/configure.py" "${CFG_ARGS[@]}"
    USER="$(whoami)" LOGNAME="$(whoami)" xcodegen generate --quiet >/dev/null 2>&1
    info "改用 $BUNDLE_PREFIX.app，重新编译…"
    xcodebuild -project Dawnus.xcodeproj -scheme Dawnus \
      -destination "id=$DEV_UDID" -allowProvisioningUpdates \
      -derivedDataPath build/DerivedData build >"$BUILD_LOG" 2>&1 \
      || { grep -E "error:" "$BUILD_LOG" | head -15; die "编译失败，完整日志: $BUILD_LOG"; }
  else
    grep -E "error:" "$BUILD_LOG" | head -15
    die "编译失败，完整日志: $BUILD_LOG"
  fi
fi
ok "编译通过"

APP_PATH=$(find build/DerivedData/Build/Products -maxdepth 3 -name "Dawnus.app" -type d | head -1)
[[ -n "$APP_PATH" ]] || die "找不到产物 Dawnus.app"

# ---------------------------------------------------------------- 7. 安装

step "7/7  安装到 $DEV_NAME"

if ! xcrun devicectl device install app --device "$DEV_UDID" "$APP_PATH" 2>&1 | tail -5; then
  die "安装失败。常见原因：手机屏幕未解锁 / 未点「信任此电脑」/ 开发者模式没开。"
fi

cat <<DONE

$(ok "安装完成 — 拂晓已装到 $DEV_NAME")

  第一次打开前，在 iPhone 上做这一步（只需一次）：
      设置 → 通用 → VPN 与设备管理 → 开发者 App → 点你的 Apple ID → 信任

  然后：
      1. 打开「拂晓」，允许「安排闹钟」权限
      2. 建一个 1–2 分钟后的闹钟，锁屏等待——验证它真的穿透静音模式响起来
      3. 长按锁屏或看灵动岛，确认实时活动的渐醒界面
      4. 点「贪睡」，确认代价会涨价并把你拉进解锁流程

  排查：
      看日志   xcrun devicectl device log stream --device $DEV_UDID
      重新装   本脚本再跑一次即可（bundle id: $BUNDLE_PREFIX.app）
      模拟器   xcrun simctl launch booted $BUNDLE_PREFIX.app -dawnus-demo ring
DONE
