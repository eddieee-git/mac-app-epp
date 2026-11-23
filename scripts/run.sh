#!/bin/zsh
# 디버그 빌드(Epp Dev)를 만들어 켠다. 실제 Epp·기존 단독 앱과 설정·데이터가 섞이지 않는다.
#
#   ./scripts/run.sh         Epp Dev를 켠다(설정에서 켠 기능이 돈다)
#   ./scripts/run.sh keepy   Keepy 하나만 단독으로 켠다(메뉴도 Keepy 것만)
#
# 같은 기능의 기존 단독 앱(예: Keepy.app)이 켜져 있으면 단축키가 겹치니 잠깐 꺼 두고 시험한다.
set -e
cd "$(dirname "$0")/.."

EPP_DEBUG=1 ./scripts/build-app.sh >/dev/null
app="build/Epp Dev.app"
osascript -e 'quit app id "com.eddieee.Epp.dev"' 2>/dev/null || true
# 예전 Epp Dev가 완전히 끝날 때까지 기다린다(끝나는 중에 열면 실패한다).
for _ in {1..30}; do
    pgrep -f "Epp Dev.app/Contents/MacOS/Epp" >/dev/null || break
    sleep 0.2
done

if [[ -n "$1" ]]; then
    open -n "$app" --args --only "$1"
    echo "$app (단독: $1)"
else
    open "$app"
    echo "$app"
fi
