#!/bin/zsh
# 자동 점검을 돌린다. Xcode 없이 Command Line Tools만으로 돌아가도록 앱 안의 --self-test 모드를 쓴다.
# 실제 설정·데이터·클립보드는 건드리지 않는다.
set -e
cd "$(dirname "$0")/.."

# 화면 문구 L("…")에 영어 번역이 다 있는지 본다. 본체와 기능은 사전이 따로 있어서 폴더마다 본다.
python3 -I - <<'EOF'
import re, pathlib, sys
failed = False
for src in [pathlib.Path("Sources/Epp"), *sorted(pathlib.Path("Modules").iterdir())]:
    if not (src / "Localization.swift").exists():
        continue
    loc = (src / "Localization.swift").read_text()
    known = set(re.findall(r'^\s*\("((?:[^"\\]|\\.)*)",', loc, re.M))
    used = set()
    for f in src.glob("*.swift"):
        if f.name == "Localization.swift":
            continue
        used |= set(re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', f.read_text()))
    missing = sorted(used - known)
    unused = sorted(known - used)
    if unused:
        print(f"{src}: 안 쓰는 번역:", unused)
    if missing:
        print(f"{src}: 영어 번역이 빠졌어요:", missing)
        failed = True
if failed:
    sys.exit(1)
print("번역 빠짐 없음")
EOF

swift build
.build/debug/Epp --self-test
