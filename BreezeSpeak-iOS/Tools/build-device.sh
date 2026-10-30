#!/bin/zsh
# 真机 Release 打包 + 安装。
#
# 默认打「App + 小组件扩展」的完整包。扩展的 bundle id 是
# com.breezespeak.app.widgets，必须有一份只属于它的描述文件；
# Xcode 没登录 Apple 账号时会报 No Accounts / No profiles，
# 这时自动降级成「只有 App」的包（小组件、锁屏、控制中心都不会出现），
# 并把缺失的东西说清楚，免得又出现「怎么没有小组件」。
set -uo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID=${DEVICE_ID:-00008122-000C45512279801C}
LOG=/tmp/breeze-device-build.log

if xcodebuild -project BreezeSpeak.xcodeproj -scheme BreezeSpeak \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath build -allowProvisioningUpdates \
    OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' build >"$LOG" 2>&1; then
  echo "✅ 完整打包成功：App + 小组件扩展（桌面 / 锁屏 / 控制中心）"
else
  if grep -qE "No Accounts|No profiles for 'com.breezespeak.app.widgets'" "$LOG"; then
    echo "⚠️  Xcode 里没有登录开发者账号，扩展 com.breezespeak.app.widgets 无法签名。"
    echo "    → 先打一份只含 App 的包；登录账号后重跑本脚本即可带上小组件。"
    ./Tools/build-device-nosign.sh
  else
    echo "❌ 打包失败："
    grep -E "error:" "$LOG" | head -10
    exit 1
  fi
fi

APP=build/Build/Products/Release-iphoneos/BreezeSpeak.app
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tail -2
xcrun devicectl device process launch --device "$DEVICE_ID" com.breezespeak.app 2>&1 | tail -1
