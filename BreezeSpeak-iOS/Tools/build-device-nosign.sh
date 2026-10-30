#!/bin/zsh
# 真机 Release 打包（临时把小组件扩展的签名与嵌入摘掉）。
#
# 为什么需要这一步：这台机器的 Xcode 没有登录 Apple 账号，扩展用的是
# com.breezespeak.app.widgets 这个子标识，没有对应描述文件，xcodebuild 会
# 直接以 "No Accounts / No profiles" 失败，连主 App 都编不出来。
# 所以打包时先把扩展从依赖链里摘掉、让它不参与签名，App 本体照常用缓存里的
# 描述文件签；打完立刻把工程文件还原，仓库状态不受影响。
# 等登录了开发者账号，直接 xcodebuild 正常打包即可，不需要这个脚本。
set -euo pipefail
cd "$(dirname "$0")/.."

PBX=BreezeSpeak.xcodeproj/project.pbxproj
BACKUP=$(mktemp /tmp/pbx.XXXXXX)
cp "$PBX" "$BACKUP"

restore() { cp "$BACKUP" "$PBX"; rm -f "$BACKUP"; }
trap restore EXIT

python3 - <<'PY'
p = 'BreezeSpeak.xcodeproj/project.pbxproj'
s = open(p).read()
s = s.replace("\t\t\t\tAB000000000000000000002D /* BreezeWidgets.appex in Embed Foundation Extensions */,\n", "")
s = s.replace("\t\t\t\tdependencies = (\n\t\t\t\t\tAB000000000000000000002A /* PBXTargetDependency */,\n\t\t\t\t);",
              "\t\t\t\tdependencies = (\n\t\t\t\t);")
s = s.replace("""				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 6S7H7VW64C;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "BreezeWidgets-Info.plist";""",
"""				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 6S7H7VW64C;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "BreezeWidgets-Info.plist";""")
open(p, 'w').write(s)
PY

plutil -lint "$PBX"

xcodebuild -project BreezeSpeak.xcodeproj -scheme BreezeSpeak \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' build \
  | grep -E "error:|BUILD" || true
