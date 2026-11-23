#!/bin/zsh
# build/Epp.app을 만든다. Xcode 없이 Command Line Tools만으로 빌드한다. Apple 실리콘 Mac 전용이다.
#
#   ./scripts/build-app.sh             릴리스 빌드 → build/Epp.app (번들 ID com.eddieee.Epp)
#   EPP_DEBUG=1 ./scripts/build-app.sh 디버그 빌드 → build/Epp Dev.app (번들 ID com.eddieee.Epp.dev)
#
# 디버그 빌드는 이름과 번들 ID가 달라서 설정(UserDefaults)과 데이터(~/Library/Application Support/Epp Dev)가
# 실제 Epp와 섞이지 않는다. 기존 단독 앱(Keepy 등)과도 섞이지 않는다.
# 아직 배포용 dmg와 업데이트 서명은 만들지 않는다(README의 "남은 일" 참고).
set -e
cd "$(dirname "$0")/.."

config=release
name=Epp
bundle_id=com.eddieee.Epp
if [[ -n "$EPP_DEBUG" ]]; then
    config=debug
    name="Epp Dev"
    bundle_id=com.eddieee.Epp.dev
fi
swift build -c $config --arch arm64

app="build/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/$config/Epp "$app/Contents/MacOS/Epp"
cp Resources/Info.plist "$app/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $name" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $name" "$plist"
if [[ $config == debug ]]; then
    # 디버그 빌드가 epp:// 주소를 가로채지 않게 한다.
    /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$plist"
fi

# "Epp Local Signing" 인증서가 있으면 그것으로, 없으면 임시 서명(scripts/sign-app.sh).
./scripts/sign-app.sh "$app" "$bundle_id"

if [[ $config == debug ]]; then
    echo "$app"
    exit 0
fi

# 배포용 dmg: 응용 프로그램 폴더로 끌어다 놓을 수 있게 바로가기를 함께 넣는다. 이름에 Info.plist의 버전을 넣는다.
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
dmg="build/Epp-$version.dmg"
staging=build/dmg
rm -rf "$staging" "$dmg" "$dmg.sig"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Epp -srcfolder "$staging" -format UDZO "$dmg"
rm -rf "$staging"

# 앱 안 업데이트가 확인하는 Ed25519 서명. 릴리스에 dmg와 함께 .sig를 올린다.
# 키(~/.config/epp/update-signing.key)가 없으면 .sig를 만들지 않고, 그 릴리스는 앱 안에서 자동 설치되지 않는다.
if [[ -f "${EPP_UPDATE_KEY:-$HOME/.config/epp/update-signing.key}" ]]; then
    swift scripts/sign-update.swift sign "$dmg" >/dev/null
fi

echo "$app"
echo "$dmg"
[[ -f "$dmg.sig" ]] && echo "$dmg.sig"
exit 0
