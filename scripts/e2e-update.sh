#!/bin/zsh
# Epp의 앱 안 업데이트가 실제로 끝까지 되는지 이 Mac 안에서만 확인해요(GitHub에 아무것도 올리지 않아요).
#
# 디버그 빌드 Epp Dev 0.1.0(지금 버전)을 임시 폴더에 두고, 이 Mac 안의 웹 서버를 GitHub 릴리스처럼 써서
# 시험 키로 서명한 "다음 버전" dmg를 내려 줘요. 켠 Epp Dev가 15초 뒤 스스로 확인 → 내려받기 →
# 서명·SHA-256·번들 ID·코드 서명 확인 → 바꿔 넣기 → 다시 켜기를 하면 통과예요.
# 기능은 모두 끈 채로 켜요. 실제 Epp, 기존 단독 앱, 진짜 서명 키는 건드리지 않아요. 1분쯤 걸려요.
# 켜져 있던 Epp Dev는 끝나요(같은 앱은 하나만 실행).
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d -t epp-e2e)
port=$(( 20000 + RANDOM % 20000 ))
server_pid=""
apps="$work/Applications"
cleanup() {
    [[ -n $server_pid ]] && kill $server_pid 2>/dev/null || true
    pkill -f "$apps/Epp Dev.app" 2>/dev/null || true
    for key in lastUpdateCheck offeredUpdateVersion updatedFromVersion; do
        defaults delete com.eddieee.Epp.dev $key >/dev/null 2>&1 || true
    done
    rm -rf "$work"
}
trap cleanup EXIT

echo "== 빌드"
EPP_DEBUG=1 ./scripts/build-app.sh >/dev/null
old_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/Epp Dev.app/Contents/Info.plist")
new_version="${old_version%.*}.$(( ${old_version##*.} + 1 ))"
echo "$old_version → $new_version"

mkdir -p "$apps" "$work/new" "$work/www"
ditto "build/Epp Dev.app" "$apps/Epp Dev.app"
# 새 버전: 같은 앱에 버전만 올려 다시 서명. dmg 안 이름은 업데이트가 찾는 "Epp.app"
ditto "build/Epp Dev.app" "$work/new/Epp.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$work/new/Epp.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 9999" "$work/new/Epp.app/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements Resources/Epp.entitlements \
    -r='designated => identifier "com.eddieee.Epp.dev"' "$work/new/Epp.app"
hdiutil create -quiet -volname Epp -srcfolder "$work/new" -format UDZO "$work/www/Epp-$new_version.dmg"

echo "== 시험 키로 서명 (진짜 서명 키는 쓰지 않아요)"
cat > "$work/sign.swift" <<'EOF'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let dmg = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
try key.signature(for: dmg).base64EncodedString().write(toFile: CommandLine.arguments[1] + ".sig", atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
EOF
public_key=$(swift "$work/sign.swift" "$work/www/Epp-$new_version.dmg")
sha=$(shasum -a 256 "$work/www/Epp-$new_version.dmg" | cut -d' ' -f1)
base="http://127.0.0.1:$port"
cat > "$work/www/latest.json" <<EOF
{"tag_name":"v$new_version","html_url":"$base/","body":"시험 릴리스","assets":[
 {"name":"Epp-$new_version.dmg","browser_download_url":"$base/Epp-$new_version.dmg","digest":"sha256:$sha"},
 {"name":"Epp-$new_version.dmg.sig","browser_download_url":"$base/Epp-$new_version.dmg.sig"}]}
EOF
python3 -m http.server $port --bind 127.0.0.1 --directory "$work/www" >/dev/null 2>&1 &
server_pid=$!
sleep 1

echo "== 자동 확인 → 자동 설치 (기본 설정 그대로, 최대 60초)"
for key in lastUpdateCheck offeredUpdateVersion; do defaults delete com.eddieee.Epp.dev $key >/dev/null 2>&1 || true; done
open -g -n "$apps/Epp Dev.app" --args -debugUpdateURL "$base/latest.json" -debugUpdatePublicKey "$public_key" \
    -enabledModules '()' -autoCheckUpdates YES -autoInstallUpdates YES
started=$SECONDS
installed=$old_version
for _ in {1..60}; do
    installed=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$apps/Epp Dev.app/Contents/Info.plist" 2>/dev/null || echo "?")
    [[ $installed == "$new_version" ]] && pgrep -f "$apps/Epp Dev.app/Contents/MacOS/Epp" >/dev/null && break
    sleep 1
done
took=$(( SECONDS - started ))

failed=0
check() { if eval "$1"; then echo "✓ $2"; else echo "✗ $2"; failed=1; fi }
check "[[ $installed == $new_version ]]" "앱이 $new_version로 바뀜 (지금 $installed, ${took}초)"
check 'pgrep -f "$apps/Epp Dev.app/Contents/MacOS/Epp" >/dev/null' "새 버전이 다시 켜짐"
check 'codesign --verify --deep --strict "$apps/Epp Dev.app" 2>/dev/null' "바꿔 넣은 앱의 코드 서명이 온전함"
check '[[ $(ls "$apps") == "Epp Dev.app" ]]' "작업 폴더·옛 앱이 남지 않음: $(ls "$apps" | tr '\n' ' ')"

(( failed == 0 )) && echo "모두 통과" || echo "실패"
exit $failed
