> 이 파일은 mac-app 공통 규칙(`../mac-app/STYLE.md`)을 2026-11-26에 복사한 거예요. Epp 저장소만으로 작업을 이어갈 수 있게 넣어 뒀어요. 아래 링크 중 `templates/release-note.md`는 [docs/templates](templates/release-note.md)에 있고, 나머지(shared/, scripts/, CHECKLIST.md)는 mac-app에만 있어요. Epp에 맞게 다른 점은 Epp의 CLAUDE.md가 우선해요.

# mac-app 공통 규칙

**Epp · Gitty · Mdy** 세 앱이 같은 사람이 만든 한 묶음으로 보이도록 맞추는 규칙이에요.

| 앱 | 하는 일 | 모양 |
|---|---|---|
| [Epp](https://github.com/eddieee-git/mac-app-epp) | 클립보드·메뉴바·스티커·타이머·캡처를 메뉴바 아이콘 하나에 모은 기능 모음 | 메뉴바 앱 |
| [Gitty](https://github.com/eddieee-git/mac-app-gitty) | Git 저장소를 파일 관리자처럼 다루는 앱 | Dock 앱 |
| [Mdy](https://github.com/eddieee-git/mac-app-mdy) | 더블클릭으로 바로 여는 마크다운 뷰어 겸 편집기 | Dock 앱 |

세 앱 모두 이 규칙을 따르고, 다르게 해야 할 이유가 있으면 그 앱의 `CLAUDE.md`에 이유를 적어 두세요.
Epp는 이 문서의 복사본을 `docs/STYLE.md`에 두고 따라요(이 문서를 고치면 그쪽에도 복사해요. 9절).

- 문서 틀: [templates/](templates)
- 앱별로 지금 어긋난 곳: [CHECKLIST.md](CHECKLIST.md)

---

## 1. 이름과 저장소

| 항목 | 규칙 | 예 |
|---|---|---|
| 앱 이름 | 짧은 영어 한 단어 | Gitty, Mdy, Epp |
| 저장소 | `eddieee-git/mac-app-<소문자 이름>` | `mac-app-gitty` |
| 번들 ID | `com.eddieee.<이름>` | `com.eddieee.Gitty` |
| 버전 | `0.x.y`. 새 기능은 x, 고친 것만 있으면 y | 0.2.0 → 0.2.1 |
| 배포 파일 | `<이름>-<버전>.dmg`, 서명 `<이름>-<버전>.dmg.sig` | `Gitty-0.2.3.dmg` |
| 태그 | `v<버전>` | `v0.2.0` |
| 다른 앱 링크 | 항상 `https://github.com/eddieee-git/mac-app-<이름>` 전체 주소로 | |

## 2. 저장소 파일 구성

```
README.md            한국어 (기본)
README.en.md         영어
CHANGELOG.md         한국어 변경 기록
CHANGELOG.en.md      영어 변경 기록
LICENSE              MIT
SECURITY.md          보안 문제 알리는 곳
CLAUDE.md            작업 규칙. 첫 줄에 이 문서를 가리키는 링크
.github/ISSUE_TEMPLATE/  bug.md, feature.md, config.yml  (scripts/apply-common-docs.py가 만들어요)
docs/images/         icon.png, 스크린샷 (영어판은 이름 뒤에 .en: main.png / main.en.png)
docs/releases/       vX.Y.Z.md — GitHub 릴리스 본문 (한국어 + 맨 아래 English)
scripts/             build-app.sh, test.sh, release.sh, make-icon.swift, sign-update.swift
Sources/<이름>/AppUpdater.swift, AppAbout.swift   공통 파일. mac-app/shared가 원본 (아래 9절. Epp는 AppUpdater만)
Package.swift        SwiftPM. Xcode 프로젝트 없이 빌드
```

`CLAUDE.md` 첫 줄:

```markdown
> 문서·UI 규칙은 ../mac-app/STYLE.md를 따른다. 다르게 할 때는 여기에 이유를 적는다.
```

Epp는 저장소만으로 작업을 이어갈 수 있게 복사본 `docs/STYLE.md`를 가리켜요. Epp README는 기능이 여러 개라 "들어 있는 기능" 표로 시작하는 자기 모양을 써요(Epp CLAUDE.md).

## 3. 글쓰기

### 말투

- README, 릴리스 노트, **앱 안의 모든 문구**는 **~어요/~해요**체예요. `~합니다`, `~한다`는 쓰지 않아요.
- CHANGELOG 항목만 짧은 명사형으로 끝내요: `그룹마다 줄 수 따로 정하기`, `업데이트 확인 403 오류 고침`.
- 영어는 짧고 평이하게. 기능 이름은 Title Case 없이 문장처럼: `Drag to reorder`.

### 굵게, 기호

- 버튼·메뉴·설정 이름처럼 화면에서 그대로 찾을 글자는 **굵게**: 설정 → **단축키**.
- 경로는 `→`로 이어요: 시스템 설정 → 개인정보 보호 및 보안.
- 키는 기호로 써요: ⌘ ⌥ ⌃ ⇧ ⌫ ←→, esc, Return, Tab. 단축키 사이에 `+`를 넣지 않아요: ⌃⌥1.
- 창이나 대화상자를 여는 메뉴·버튼에는 말줄임표 `…`(한 글자)를 붙여요: 설정…, 업데이트 확인….

### 용어

| 쓰는 말 | 안 쓰는 말 |
|---|---|
| 설정 | 환경설정, 옵션 |
| 내려받기 | 다운로드 (단, Finder의 "다운로드" 폴더 이름은 그대로) |
| 메뉴바 | 메뉴 막대, 상태 막대 |
| 단축키 | 핫키, 바로가기 키 |
| 지우기 / 삭제 (확인 버튼) | 제거 |
| <앱> 종료 | 끝내기, 나가기 |
| 손쉬운 사용, 화면 기록, 그래도 열기, 개인정보 보호 및 보안 | macOS 화면에 나오는 이름과 다른 말 |
| Apple 실리콘 | M칩, ARM |

## 4. README

틀: [templates/README.md](templates/README.md), [templates/README.en.md](templates/README.en.md)

### 머리

```html
<p align="center"><img src="docs/images/icon.png" width="96" alt="<이름> 아이콘"></p>
<h1 align="center"><이름></h1>
<p align="center">한 줄 소개 (무엇을 하는 macOS 앱인지)<br>두 번째 줄 (왜 좋은지, 한 문장)</p>
<p align="center">최신 버전 내려받기 · 설치 · 쓰는 방법 · 단축키 · 자주 묻는 질문 · 변경 기록 · English</p>
<p align="center">스크린샷 1~2장 (width 340~720)</p>
```

- 아이콘은 `docs/images/icon.png`, 너비 **96**.
- 바로가기 줄에는 그 README에 실제로 있는 섹션만 넣고, **최신 버전 내려받기**(맨 앞)와 **English / 한국어**(맨 뒤)는 항상 넣어요.
- 스크린샷은 최소 1장. 한국어 README에는 한국어 화면, 영어 README에는 영어 화면.

### 섹션 순서

필수는 ●, 해당될 때만 ○.

| 순서 | 한국어 | English | |
|---|---|---|---|
| 1 | 특징 | Features | ● |
| 2 | 설치 | Install | ● |
| 3 | 쓰는 방법 | How to use | ● |
| 4 | 단축키 | Shortcuts | ○ |
| 5 | 설정 | Settings | ○ |
| 6 | 자주 묻는 질문 | FAQ | ● (적어도 "어떤 정보를 보내나요?" 하나) |
| 7 | 지우기 | Uninstall | ● |
| 8 | 직접 빌드하기 | Build from source | ● |
| 9 | 라이선스 | License | ● |
| 10 | 다른 앱 | More apps | ● |

- **특징**: `- **짧은 이름**: 한 문장.` 형식. 마지막 두 줄은 항상 업데이트와 언어:
  `- **앱 안 업데이트**: …` / `- **한국어·영어**: …`
- **설치**: 맨 앞에 요구 사항 한 줄(`Apple 실리콘 Mac, macOS 14 이상`). 그다음 내려받기 → Applications로 끌기 → 처음 열 때 경고 넘기기(macOS 15+ / 14 나눠서) → `xattr` 한 줄 → 권한(필요한 앱만).
- **설정**: `| 항목 | 설명 |` 표. 기본값은 설명 끝에 `(기본 끔)`처럼.
- **단축키**: `| 키 | 동작 |` 표. 전역 단축키와 창 안 단축키를 나눠요.
- **다른 앱**: 모든 앱을 한 줄씩. 자기 자신은 빼요. 내용은 [templates/more-apps.md](templates/more-apps.md)에서 그대로 복사해요.
- 앱이 커서 쓰는 방법이 길어지면 `docs/guide.md`(+ `.en.md`)로 빼고 README에는 요약과 링크만 둬요.

## 5. 변경 기록과 릴리스 노트

### CHANGELOG.md / CHANGELOG.en.md

```markdown
# 변경 기록

버전마다 자세한 내용은 [docs/releases](docs/releases)와 [GitHub 릴리스](https://github.com/eddieee-git/mac-app-<이름>/releases)에 있어요. English: [CHANGELOG.en.md](CHANGELOG.en.md)

## 0.2.0 (2026-11-14)

- 짧은 명사형 항목
```

- 한 파일에 두 언어를 섞지 않아요. 제목에 날짜 `(YYYY-MM-DD)`를 꼭 넣어요.
- 새 버전이 위로 와요.

### docs/releases/vX.Y.Z.md (GitHub 릴리스 본문)

틀: [templates/release-note.md](templates/release-note.md). 섹션 순서는 고정이고, 내용이 없는 섹션은 빼요.

1. 한 줄 요약 (제목 없이 첫 문단)
2. `## 설치와 업데이트`: 이전 버전 사용자 / 처음 설치하는 사람
3. `## 새 기능`
4. `## 바뀐 점`
5. `## 고친 점`
6. `## 보안`
7. `## 알려진 제한`: 지원 환경과 서명 경고는 매번 적어요
8. `## English`: 위 내용을 줄여서

## 6. 앱 화면 (UI)

### 메뉴바 메뉴 (메뉴바 앱: Epp)

```
[앱 고유 항목 …]
────────────
설정…                 ⌘,
업데이트 확인…        (새 버전이 있으면 "새 버전 X.Y.Z 설치…" + arrow.down.circle 아이콘)
시작 안내             (권한이 필요한 앱만)
────────────
<이름> 종료           ⌘Q
```

- 종료 항목 이름은 항상 `<이름> 종료`.
- 메뉴바 아이콘은 SF Symbol 또는 템플릿 이미지(밝은·어두운 메뉴바에서 다 보여야 해요).

### 앱 메뉴 (Dock 앱: Gitty, Mdy)

```
<이름>에 관하여
업데이트 확인…
────────────
설정…   ⌘,
────────────
<이름> 숨기기 ⌘H / 기타 숨기기 / 모두 보기
────────────
<이름> 종료  ⌘Q
```

### 설정 창

- 창 제목: `<이름> 설정`. ⌘,로 열고 ⌘W·esc로 닫혀요. 크기는 고정(너비 460~640).
- 위쪽 **세그먼트 탭**으로 나눠요. 순서:

  **일반** · (앱 고유 탭들) · **단축키** · **정보**

  설정이 아주 적으면 탭 없이 한 장도 돼요. 그래도 아래 섹션 순서는 지켜요.
- SwiftUI `Form` + `.formStyle(.grouped)`.
- **일반** 탭에 꼭 있는 것 (이 순서로, 맨 아래):
  - 로그인 시 실행
  - 언어: 시스템 / 한국어 / English (기본 시스템)
  - 업데이트 섹션 (아래)
- **정보** 탭: 아이콘, 이름, 버전, GitHub · 변경 기록 · 문제 알리기 링크, 다른 앱 목록. 공통 `AppAboutSections`를 `Form`에 넣어요. 한 장짜리 설정은 맨 아래에 넣어요(Gitty, Mdy). Epp는 공통 파일을 쓰지 않고 자기 정보 화면을 써요.
- 권한이 필요한 앱은 권한 줄마다 상태를 색으로: 허용됨 초록 / 필요 주황, 옆에 **허용하기** 버튼.

### 업데이트 (모든 앱 같은 방식)

- 설정 → 일반 → 업데이트 섹션:
  - **새 버전 자동으로 확인** (기본 켬, 하루 한 번)
  - **새 버전 자동으로 설치** (기본 켬)
  - **지금 확인** 버튼과 상태 한 줄: "최신 버전이에요" / "새 버전 X.Y.Z가 있어요"
- 확인은 GitHub 공개 API 요청 하나만. 막히면(403) 릴리스 페이지로 다시 확인.
- 설치 전에 **Ed25519 `.sig` → SHA-256 → 코드 서명**을 모두 확인하고, 하나라도 틀리면 설치하지 않아요.
- 새 버전이 있으면 메뉴바 메뉴의 업데이트 항목이 `새 버전 X.Y.Z 설치…`로 바뀌어요.
- 코드는 공통 파일 `AppUpdater.swift` 하나예요(9절). 설정 칸은 `AppUpdaterSection`, 메뉴 항목은 `AppUpdater.shared.makeMenuItem()`을 써요.
- 자동 설치는 앱을 앞에 두고 쓰고 있지 않을 때만 해요(쓰다가 다른 앱으로 넘어가면 그때, 아니면 한 시간마다 다시 봐요).
- 사용자가 직접 확인하거나 "새 버전 X 설치…"를 누르면 **묻는 창 없이 바로** 받아 바꿔 넣고 다시 켜요. 창은 앱 안에서 설치할 수 없을 때(자동 설치를 껐거나, 바꿔 넣을 수 없는 위치이거나, 서명 없는 릴리스)만 띄우고, 자동 확인에서는 버전마다 한 번만 띄워요.

### 언어

- 문구는 한국어 원문을 키로 써요. Epp는 `L("…")`, Gitty·Mdy는 `tr("…")`(끼워 넣는 값을 문자열 보간으로 쓰는 방식)이에요. `NSLocalizedString`은 쓰지 않아요.
- 영어 번역은 사전 하나에 모아요(Epp `Localization.swift`, Gitty·Mdy `Resources/en.json`). 빠진 번역이 있으면 `test.sh`가 실패해요.
- 처음 실행 때는 시스템 언어를 따라요. 한국어가 아니면 영어.

### 처음 실행

- 권한이 필요한 앱은 **시작 안내** 창을 띄워요: 권한 줄 + 대표 단축키 + "다음부터 열지 않기". 메뉴바 메뉴에서 다시 열 수 있어요.
- 권한이 필요 없는 앱은 기본 창(또는 예시 내용)을 바로 보여 줘요.

### 단축키

- ⌘, 설정 · ⌘W 창 닫기 · ⌘Q 종료 · esc 팝업/바 닫기는 모든 앱 공통.
- 전역 단축키 기본 보조 키는 ⌃⌥. 설정 → 단축키에서 바꾸거나 끌 수 있어야 하고, 다른 앱과 겹치면 알려 줘요.

### 손쉬운 사용

- 아이콘만 있는 버튼에는 `.help(…)`와 VoiceOver 라벨을 둘 다.
- "동작 줄이기"가 켜져 있으면 깜빡임·애니메이션을 끄거나 줄여요.
- 색은 시스템 강조 색(`accentColor`)을 기본으로. 앱 고유 색은 꼭 필요한 곳에만.

### 알림과 확인 창

- 제목은 무엇이 일어났는지(`업데이트하지 못했어요`), 본문은 왜 그런지와 할 수 있는 일.
- 버튼은 동사로: **업데이트**, **삭제**, **취소**. "예/아니요"는 쓰지 않아요.
- 되돌릴 수 있는 삭제는 묻지 않고 **되돌리기** 토스트를, 되돌릴 수 없는 삭제는 확인 창을.

## 7. 지원 환경과 빌드

- 기본: **Apple 실리콘, macOS 14 이상**. 다르게 지원하는 앱은 README 설치 맨 앞 줄에 정확히 적어요(Gitty·Mdy는 Intel Mac도 지원).
- 빌드는 `./scripts/build-app.sh` 하나로 `build/<이름>.app`과 `build/<이름>-<버전>.dmg`가 나와요.
- 점검은 `./scripts/test.sh`, 릴리스는 `./scripts/release.sh <버전>`. 이 이름과 사용법은 모든 앱이 같아요.
- Apple 공증은 하지 않아요. 그래서 README·릴리스 노트에 첫 실행 경고 안내를 항상 넣어요.

## 8. 개인정보 문구 (README 자주 묻는 질문에 그대로)

> **어떤 정보를 보내나요?**
> 업데이트 확인 때 GitHub 공개 API에 최신 릴리스를 묻는 요청 하나만 보내요. <앱이 다루는 내용>은 어디에도 보내지 않아요. 설정에서 자동 확인을 끄면 그것도 보내지 않아요.

외부와 더 통신하는 앱(Gitty의 git push, Epp 타이머의 iCal 주소, Mdy 문서의 외부 이미지)은 그 내용을 이 답에 덧붙여요.

## 9. 공통 파일과 스크립트

| 파일 | 하는 일 |
|---|---|
| [shared/AppUpdater.swift](shared/AppUpdater.swift) | 업데이트 확인·내려받기·확인·바꿔 넣기, 설정의 업데이트 칸, 메뉴 항목 |
| [shared/AppAbout.swift](shared/AppAbout.swift) | 설정의 정보 칸과 다른 앱 목록 (Gitty, Mdy) |
| [scripts/sync-shared.sh](scripts/sync-shared.sh) | `shared/*.swift`를 세 앱(또는 이름을 준 앱)에 복사. Epp에는 `AppUpdater.swift`만. `--check`는 다르면 실패 |
| [scripts/apply-common-docs.py](scripts/apply-common-docs.py) | SECURITY.md, 이슈 양식, README의 "다른 앱", CLAUDE.md 첫 줄을 Gitty·Mdy(또는 이름을 준 앱)에 만들기. Epp 문서는 건드리지 않아요 |
| [scripts/e2e-update-test.sh](scripts/e2e-update-test.sh) | 시험용 앱으로 자동 확인 → 내려받기 → 서명 확인 → 바꿔 넣기 → 다시 켜기를 끝까지 확인 |

- 공통 파일은 **앱 저장소에서 고치지 않아요.** `shared/`에서 고치고 `sync-shared.sh`를 돌린 뒤, 세 앱의 `test.sh`와 `e2e-update-test.sh`를 돌려요.
- 앱마다 다른 값(이름, 저장소, 서명 키, 설치 방식)은 각 앱의 `UpdaterSetup.swift`에만 둬요.
- 앱이 늘거나 소개 문구가 바뀌면 `shared/AppAbout.swift`의 `AppFamily.members`, `apply-common-docs.py`의 `APPS`, `templates/more-apps.md`를 함께 고쳐요.
- 이 문서(STYLE.md)를 고치면 `../Epp/docs/STYLE.md`에도 복사해요. 그 파일 맨 위의 "복사본" 안내 줄은 남기고 날짜만 바꿔요.
