#!/bin/bash
# 把 BreezeSpeak 装到真机 iPad 并启动。
# 前置条件：1) iPad 用数据线连上 Mac 并「信任此电脑」；2) Xcode 已登录 Apple ID。
# 用法：./Tools/run-on-ipad.sh [设备UDID]
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
PROJECT_DIR="$(pwd)"

BUNDLE_ID="com.breezespeak.app"
DEVICE_UDID="${1:-00008122-000C45512279801C}"

echo "==> 目标设备：$DEVICE_UDID"

# 1. 检查设备是否在线
INFO="$(xcrun devicectl list devices 2>/dev/null)"
if ! echo "$INFO" | grep -q "$DEVICE_UDID"; then
  echo "✗ 找不到这台设备。请用数据线连接 iPad，并在 iPad 上点「信任」。"
  exit 1
fi
if ! echo "$INFO" | grep "$DEVICE_UDID" | grep -qE "[[:space:]](available|connected)[[:space:]]"; then
  echo "✗ 设备已配对但当前离线（未连接）。"
  echo "  处理：插上数据线 → 解锁 iPad → 弹窗点「信任」→ 重新运行本脚本。"
  echo "  若要无线连接：Xcode → Window → Devices and Simulators → 勾选 Connect via network。"
  exit 1
fi
echo "✓ 设备在线"

# 2. 检查 Xcode 是否登录了 Apple 账号（免费账号即可）
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  echo "✗ 钥匙串里没有 Apple Development 证书。"
  echo "  处理：打开 Xcode → Settings → Accounts → 用 Apple ID 登录 → Manage Certificates 里加一个 Apple Development。"
  exit 1
fi
echo "✓ 找到 Apple Development 证书"

# 3. 构建（自动签名 + 自动把本机设备注册进描述文件）
echo "==> 构建中（首次会自动注册设备并生成描述文件，需要联网）…"
xcodebuild \
  -project BreezeSpeak.xcodeproj \
  -scheme BreezeSpeak \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -derivedDataPath "$PROJECT_DIR/.build/device" \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  build 2>&1 | tee /tmp/breezespeak-device-build.log | grep -E "error:|No Accounts|No profiles|BUILD" | head -20

if ! grep -q "BUILD SUCCEEDED" /tmp/breezespeak-device-build.log; then
  echo ""
  echo "✗ 构建失败，常见原因："
  echo "  · No Accounts        → Xcode 未登录 Apple ID（Xcode → Settings → Accounts）"
  echo "  · No profiles found  → 同上，登录后会自动生成"
  if grep -q "No Accounts" /tmp/breezespeak-device-build.log; then
    echo ""
    echo "  检测到 No Accounts：请先在 Xcode 里登录 Apple ID 再运行本脚本。"
    open -a Xcode
  fi
  exit 1
fi

APP_PATH="$PROJECT_DIR/.build/device/Build/Products/Debug-iphoneos/BreezeSpeak.app"
if [ ! -d "$APP_PATH" ]; then
  echo "✗ 没找到构建产物：$APP_PATH"
  exit 1
fi
echo "✓ 构建成功：$APP_PATH"

# 4. 安装并启动
echo "==> 安装到 iPad…"
if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"; then
  echo "✗ 安装失败。若提示签名/描述文件不含该设备，拔插一次数据线后重试。"
  exit 1
fi
echo "✓ 安装完成"

echo "==> 启动…"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || true

echo ""
echo "完成。注意：免费开发者账号签出来的 App 有效期 7 天，到期重跑本脚本即可。"
