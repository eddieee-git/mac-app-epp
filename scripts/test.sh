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
    # 사전은 보통 Localization.swift에, 타이머는 ClockySettings.swift 안에 있다(enum Localization이 있는 파일).
    loc_files = [f for f in src.glob("*.swift") if "enum Localization" in f.read_text()]
    if not loc_files:
        continue
    loc_file = loc_files[0]
    loc = loc_file.read_text()
    known = set(re.findall(r'^\s*\("((?:[^"\\]|\\.)*)",', loc, re.M))
    # 사전이 ("한국어", "English") 목록이 아니라 "한국어": "English" 꼴인 기능(스티커)도 읽는다.
    known |= set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"', loc, re.M))
    used = set()
    for f in src.glob("*.swift"):
        text = f.read_text()
        if f == loc_file:
            # 사전 파일에 섞인 코드(ClockySettings)의 L("…")도 센다. 사전 줄 자체는 L(로 시작하지 않는다.
            text = text.split("enum Localization")[0]
        used |= set(re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', text))
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

# 타이머의 단위 시험(Swift Testing). Xcode 없이 Command Line Tools에 든 Swift Testing을 쓰는데,
# swift test가 그 위치를 스스로 찾지 못하므로 경로를 알려 준다. 시험은 따로 빌드한다(.build/tests).
dev=/Library/Developer/CommandLineTools/Library/Developer
swift test --scratch-path .build/tests \
    -Xswiftc -target -Xswiftc arm64-apple-macosx14.0 \
    -Xswiftc -F -Xswiftc $dev/Frameworks \
    -Xlinker -rpath -Xlinker $dev/Frameworks \
    -Xlinker -rpath -Xlinker $dev/usr/lib 2>&1 | grep -E "✘|error:|Test run with|recorded an issue" || true
