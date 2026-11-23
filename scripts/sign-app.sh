#!/bin/zsh
# 앱 하나에 코드 서명을 한다: ./scripts/sign-app.sh <앱 경로> <번들 ID>
#
# scripts/make-signing-cert.sh로 만든 "Epp Local Signing" 인증서가 있으면 그것으로 서명하고,
# 서명 조건(designated requirement)을 "이 번들 ID + 이 인증서"로 정한다. 그러면 macOS가 같은 인증서로 서명한 Epp만
# Epp로 보고 권한(손쉬운 사용·화면 기록)을 이어 준다. 다시 빌드하거나 업데이트해도 권한이 유지된다.
# 인증서가 없으면(다른 Mac 등) 임시 서명을 하고 서명 조건을 번들 ID로만 정한다.
# 강화 런타임(--options runtime)을 켜서 다른 라이브러리를 끼워 넣지 못하게 한다.
set -e
cd "$(dirname "$0")/.."
app=$1
bundle_id=$2
identity="Epp Local Signing"

hash=$(security find-certificate -c "$identity" -Z 2>/dev/null | awk '/SHA-1 hash:/ {print $3}' | head -1)
if [[ -n $hash ]]; then
    codesign --force --sign "$hash" --options runtime --entitlements Resources/Epp.entitlements \
        -r="designated => identifier \"$bundle_id\" and certificate leaf = H\"$hash\"" "$app"
else
    echo "알림: \"$identity\" 인증서가 없어 임시 서명해요(./scripts/make-signing-cert.sh)." >&2
    codesign --force --sign - --options runtime --entitlements Resources/Epp.entitlements \
        -r="designated => identifier \"$bundle_id\"" "$app"
fi
