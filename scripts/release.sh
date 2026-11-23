#!/bin/zsh
# GitHub 릴리스를 만든다: 점검 → 빌드(dmg + .sig) → 태그 → 릴리스에 dmg와 .sig 첨부.
# 버전은 Resources/Info.plist의 CFBundleShortVersionString을 쓴다. 릴리스 노트는 docs/releases/v<버전>.md.
# 앱 안 업데이트는 GitHub 공개 API로 최신 릴리스를 묻기 때문에, 저장소가 공개일 때만 사용자에게 닿는다.
# 사용: ./scripts/release.sh   (GitHub에 올리기 전에 꼭 사용자에게 확인받는다)
set -e
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
tag="v$version"
notes="docs/releases/$tag.md"

if [[ ! -f "$notes" ]]; then
    echo "릴리스 노트가 없어요: $notes"
    exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "이미 있는 태그예요: $tag (Info.plist의 버전을 올려 주세요)"
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "커밋하지 않은 변경이 있어요. 먼저 커밋해 주세요."
    exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "main 브랜치에서 내 주세요."
    exit 1
fi

./scripts/test.sh
./scripts/build-app.sh
if [[ ! -f "build/Epp-$version.dmg.sig" ]]; then
    echo "업데이트 서명(.sig)이 없어요. ~/.config/epp/update-signing.key를 확인해 주세요."
    exit 1
fi

git tag -a "$tag" -m "Epp $version"
git push origin "$tag"
# 릴리스 노트 끝에 dmg의 SHA-256을 붙여 올린다(저장소의 노트 파일은 그대로 둔다).
body=$(mktemp)
cat "$notes" > "$body"
printf '\n## SHA-256\n\n```\n%s  Epp-%s.dmg\n```\n' "$(shasum -a 256 "build/Epp-$version.dmg" | cut -d' ' -f1)" "$version" >> "$body"
gh release create "$tag" "build/Epp-$version.dmg" "build/Epp-$version.dmg.sig" --title "Epp $version" --notes-file "$body"
rm -f "$body"
echo "릴리스를 만들었어요: $tag"
echo "확인: gh api repos/eddieee-git/mac-app-epp/releases/latest --jq '.tag_name, .assets[].digest'"
