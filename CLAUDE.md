> 문서·UI 규칙은 ../mac-app/STYLE.md를 따른다(말투 "~해요", 메뉴·설정 모양). 다르게 할 때는 여기에 이유를 적는다.

# Epp 개발 메모

Epp(Eddie's app)는 따로 있던 메뉴바 앱들을 **기능(module)** 으로 모은 macOS 메뉴바 앱이다.
Swift Package 하나로, Xcode 없이 Command Line Tools만으로 빌드한다. Apple 실리콘, macOS 14 이상.

## 사용자

- 코딩을 잘 모르는 분이다. 한국어로, 쉬운 말로 설명한다.
- 지금 어느 단계인지와 남은 단계를 순서대로 알려 준다. 사소한 기술 결정은 무난한 쪽으로 정하고 무엇을 골랐는지 말한다.
- GitHub에 올리기와 새 버전 내기는 하기 전에 꼭 확인받는다.

## 지켜야 할 것

- **기존 단독 앱 저장소(../Clocky, ../Floaty, ../Grabby, ../Keepy, ../Peeky)는 건드리지 않는다.** 코드는 복사해 와서 고친다. 복사한 뒤로는 따로 간다.
- **사용자의 실제 앱·데이터를 건드리지 않는다.** 시험은 디버그 빌드 `Epp Dev`(번들 ID `com.eddieee.Epp.dev`, 데이터 `~/Library/Application Support/Epp Dev/`)로 한다.
- **기능은 처음에 모두 꺼져 있다.** 꺼진 기능은 객체를 만들지 않는다(타이머·단축키·창 없음).
- 사용자 문구는 한국어로 쓰고 영어 번역을 함께 넣는다.
- Apple 계정이 필요한 기능(iCloud, 공증, Developer ID 서명)은 만들지 않는다.

## 명령

```bash
./scripts/test.sh                 # 번역 빠짐 확인 + 빌드 + 자체 점검(본체 + 모든 기능) + 타이머 단위 시험(swift test). 실제 설정·데이터는 안 건드림
./scripts/run.sh                  # Epp Dev 빌드 후 켜기
./scripts/run.sh keepy            # Keepy 하나만 단독으로 켜기(개발·시험용)
./scripts/build-app.sh            # build/Epp.app (릴리스)
EPP_DEBUG=1 ./scripts/build-app.sh  # build/Epp Dev.app (디버그, -showInDock YES 인자 동작)
swift scripts/make-icon.swift     # Resources/AppIcon.icns, docs/images/icon.png 다시 그리기
./scripts/e2e-update.sh           # 앱 안 업데이트를 이 Mac 안에서 끝까지 시험(시험 키·로컬 서버, Epp Dev). 1분쯤
"build/Epp Dev.app/Contents/MacOS/Epp" -debugCycleModules keepy,clocky,floaty,grabby -debugCycleTimes 10 -enabledModules '()'
                                  # 기능 켜기/끄기 반복 뒤 남은 객체·단축키·창 확인(CYCLE OK). 메뉴바(peeky)는 실제 메뉴바를 건드려 뺀다
./scripts/release.sh              # 점검 → dmg + .sig → 태그 push → gh release (main에서만, 하기 전에 사용자 확인)
swift scripts/sign-update.swift public  # 업데이트 서명 키의 공개 키 출력
```

## 업데이트·릴리스

- 업데이트 코드 `Sources/Epp/AppUpdater.swift`는 `../mac-app/shared/AppUpdater.swift` 복사본이다. 여기서 고치지 않는다.
  원본이 바뀌면 다시 복사한다(`cp ../mac-app/shared/AppUpdater.swift Sources/Epp/`). Epp 값은 `UpdaterSetup.swift`에만.
- 하루 한 번 GitHub(`eddieee-git/mac-app-epp`) 최신 릴리스를 묻고, 기본은 Epp를 쓰지 않을 때 알아서 설치한다.
  설정 → 일반 → 업데이트, 메뉴의 "업데이트 확인…". **저장소가 비공개인 동안에는 릴리스를 찾지 못한다**(공개 API라서).
- 디버그 빌드(Epp Dev)는 `-debugUpdateURL`을 줬을 때만 확인한다(`AppUpdater.shouldRun`).
- **업데이트 서명 키**: 비밀 키는 저장소 밖 `~/.config/epp/update-signing.key`(`EPP_UPDATE_KEY`로 바꿀 수 있음). 공개 키는 `UpdaterSetup.swift`.
  **읽어서 출력하거나 커밋하지 않는다. 잃어버리면 설치된 Epp가 새 버전을 자동으로 받지 못하니 따로 백업한다.**
- 릴리스 순서: Info.plist 버전(+`CFBundleVersion`) 올리기 → `docs/releases/v<버전>.md` → 커밋·main push → `./scripts/release.sh`
  → `gh api repos/eddieee-git/mac-app-epp/releases/latest --jq '.tag_name, .assets[].digest'`가 `shasum -a 256 build/Epp-<버전>.dmg`와 같은지.

## 구조

```
Sources/EppKit/     모든 기능이 같이 쓰는 부품
  EppModule.swift     기능 약속(EppModule), 기능 정보(EppModuleInfo), 본체가 넘겨주는 것(EppContext)
  HotKey.swift        KeyCombo, 전역 단축키(번호 자동 배정, 처리기 하나)
  EppLanguage.swift   언어(설정의 "language"), 다시 열기, esc로 닫히는 창
  EppPermissions.swift 권한 상태·요청(손쉬운 사용, 화면 기록), 기능이 알리는 필요(EppPermissionNeed)
  EppLog.swift        공통 진단 로그
  EppShortcuts.swift  단축키 줄(EppShortcutRow), 기능이 알리는 전역 단축키(EppShortcutInfo)
  EppSettings.swift   기능 설정 틀(EppSettingsPage, EppSettingsTab), 시작하기(EppStepList), 권한 줄(EppPermissionRow)
Sources/Epp/        본체
  main.swift          Dock 아이콘(설정 "showInDock", 기본 끔), --self-test, --only <id>(단독 실행), 하나만 실행
  AppDelegate.swift   메뉴바 아이콘·메뉴(기능마다 하위 메뉴), Dock 메뉴, 앱 메뉴, epp:// 주소, DockIcon
  ModuleList.swift    들어 있는 기능 목록(순서대로 메뉴·설정에 나옴)
  ModuleManager.swift 켜기/끄기, 기능별 저장소(UserDefaults "<번들 ID>.<id>", 폴더 "<Epp>/<이름>")
  SettingsWindow.swift 설정 창: 왼쪽 설정 검색 + 일반 + 기능 목록, 오른쪽 고른 쪽(기능은 EppSettingsPage)
  SelfTest.swift      본체 점검(공통 업데이트 포함) 후 모든 기능의 runSelfTest()
  AppUpdater.swift    공통 업데이트(../mac-app/shared 복사본) / UpdaterSetup.swift: Epp 값(저장소, 공개 키)
Modules/<이름>/     기능 하나 (예: Modules/Keepy)
```

## 새 기능 옮기는 순서

1. `Modules/<이름>/`에 기존 앱의 `Sources/<이름>/*.swift`를 복사한다. 빼는 것: `main.swift`, `AppDelegate.swift`, `AppUpdater.swift`, `AppAbout.swift`, `UpdaterSetup.swift`, `AppRelauncher.swift`.
2. `<이름>Module.swift`를 만들어 `EppModule`을 따른다. 기존 `AppDelegate`의 내용을 옮긴다:
   - 시작 → `start()`, 끝낼 때 저장 → `stop()` (타이머·단축키·창을 모두 멈춘다)
   - 메뉴바 메뉴의 고유 항목 → `fillMenu(_:)` (설정…/업데이트/종료는 본체가 붙인다)
   - 설정 창 → `settingsTabs()`, 시작 안내 창 → `makeGettingStarted()` (아래 "화면 규칙". 정보·로그인·언어·업데이트는 뺀다)
   - URL 스킴 → `handle(url:)` (`epp://<id>/<명령>`)
3. 저장 위치를 바꾼다: `UserDefaults.standard` → `context.defaults`, `Application Support/<이름>` → `context.dataDirectory`.
4. 언어: 기능의 `Localization.isKorean`은 `EppLanguage.isKorean`을 돌려준다. 단축키는 EppKit의 `HotKey(combo:action:)`.
5. `Package.swift`의 `modules`와 `Sources/Epp/ModuleList.swift`에 한 줄씩 더한다.
6. `./scripts/test.sh` → `./scripts/run.sh <id>`로 단독 확인 → `./scripts/run.sh`로 함께 확인.

## 규칙과 함정

- **보안**
  - 개인 내용(클립보드 기록 등)을 디스크에 쓸 때는 `EppCrypto(account: "<기능>-<무엇>")`로 암호화한다. 키는 키체인(서비스 = 번들 ID).
    예전 평문 파일은 그대로 읽고 다음 저장 때 암호화한다. 읽지 못한 파일은 덮어쓰지 말고 옆에 남긴다(`history-unreadable-…`).
    임시 서명이라 키체인 항목은 다른 앱도 묻지 않고 읽을 수 있다(복사·백업된 파일을 지키는 용도).
  - `epp://` 주소는 웹페이지도 연다. `handle(url:)`은 **창 열기처럼 해가 없는 명령만** 받고 모르는 명령은 무시한다(기본 동작으로 넘기지 않는다).
    묻지 않고 화면을 찍거나 데이터를 지우는 명령은 넣지 않는다. 본체가 10초에 5번으로 막는다(`RateGate`).

- **설정 Form에는 `.scrollContentBackground(.hidden)`**. Form이 그리는 배경은 바탕화면 색이 묻어나 남색으로 보인다(시스템 설정은 회색). `EppSettingsPage`가 기능 탭에 붙여 준다.
- **긴 글에 `.fixedSize(horizontal: false, vertical: true)`를 GroupBox 안에서 쓰지 않는다.** 폭 없이 재져 한 글자씩 줄이 바뀌고 창 전체가 밀렸다.
- **SwiftUI `ForEach`에 기능 타입 목록(`[any EppModule.Type]`)을 바로 넣으면 컴파일러가 죽는다.** `ModuleList.infos`(값 목록)를 쓴다.
- 기능의 `@AppStorage` 키는 본체 UserDefaults에 저장되므로 `<id>.` 접두어를 붙인다(예: `keepy.settingsTab`).
- 손쉬운 사용·화면 기록 권한은 Epp 하나에 주어진다. 기존 단독 앱 권한과는 별개다.
- 전역 단축키는 모두 Epp 한 앱이 등록한다. 기능끼리 같은 키를 쓰면 먼저 등록한 기능이 받는다.

## Keepy (Modules/Keepy)

원본: ../Keepy 0.1.2 (커밋 2801840). 바뀐 점:
- `AppDelegate` → `KeepyModule`. 앱 아이콘으로 열기(copyOnly), 로그인 항목으로 켜졌는지 확인은 뺐다.
- `AppSettings.shared`는 `KeepyModule`이 `context.defaults`로 만들어 넣는다.
- 설정: 일반 · 제외 앱 · 단축키 (정보·로그인·언어·업데이트는 본체로).
- 시작 안내 창(WelcomeWindow)을 지우고 설정 맨 위 시작하기 상자로 바꿨다. 권한 없이 붙여 넣으면 `context.showGettingStarted()`.
- 단축키 겹침 경고에 단독 Keepy 앱(`com.eddieee.Keepy`)도 넣었다.
- 기록(history.json, blobs/)은 `EppCrypto(account: "keepy-history")`로 암호화. 고정하지 않은 기록은 `historyMaxAgeDays`(기본 30일)가 지나면 지운다(시작할 때·한 시간마다).

## Peeky (Modules/Peeky)

원본: ../Peeky 0.3.4 (커밋 9911bf1). 바뀐 점:
- `AppDelegate` → `PeekyModule`. 그룹 아이콘·‹ › 버튼·구분선은 Peeky가 직접 만든다(Peeky의 일). `stop()`에서 모두 지우고 구분선은 펼친 뒤 지운다.
- 자기 `HotKey.swift`를 지우고 EppKit `HotKey(keyCode:modifiers:action:)`을 쓴다. **기능마다 Carbon 처리기를 따로 두면 번호가 겹쳐 다른 기능의 단축키가 불린다.**
- `Preferences.shared`, `PeekyStorage.defaults`·`logPath`는 `PeekyModule.init`에서 Epp가 준 값으로 채운다.
  `NSStatusItem Preferred Position …`(`StatusItemPlacement`)만은 macOS가 앱의 기본 UserDefaults에서 읽으므로 그대로 둔다.
- 숨기기가 Epp 아이콘까지 밀어내지 않게 `context.hostStatusItems()`를 보호 목록에 넣는다. Epp 아이콘은 `autosaveName = "EppMain"`, 처음 자리는 오른쪽 끝에서 170.
- 오른쪽 클릭 메뉴의 "Peeky 종료"와 업데이트 항목을 뺐다(종료는 Epp 메뉴). 설정에서 로그인·언어·업데이트·정보를 뺐다.
- 진단 로그: 자기 로그 파일·설정을 없애고 `ItemStore.log` → `EppLog.write("메뉴바", …)`.
- `Preferences.shared`가 `Preferences!`라서 `let prefs = Preferences.shared`처럼 쓰면 Optional이 된다. 타입을 적는다(`let prefs: Preferences = …`).

## Floaty (Modules/Floaty) = 스티커

원본: ../Floaty (커밋 62a4ae5). 바뀐 점:
- `AppDelegate` → `FloatyModule`. 메뉴바 아이콘(압정 메모지)·⌥클릭 새 스티커·한 번만 실행(SingleInstance)은 뺐다. 메뉴는 Epp의 "스티커 ▸".
- 앱 메뉴(파일 ⌘N·⌘D·⌘S·⌘P, 편집의 찾기·서식 없이 붙여넣기, 서식, 윈도우 ⌘\`)는 `mainMenus()`로 넘기고 본체가 합친다.
- 테마는 `NSApp.appearance`가 아니라 스티커 창에만(`FloatyTheme`: StickyPanel, 스티커 관리 창, 되돌리기 알림). 앱 전체를 바꾸면 다른 기능 화면까지 바뀐다.
- 언어는 Epp를 따른다(`Localization.language` = `EppLanguage`). 바로 바뀌던 언어 고르기는 뺐다.
- `KeyCombo`·`HotKey`는 EppKit 것. `HotKey.swift`에는 `HotKeyAction`과 기본값(`KeyCombo.defaults`, `renameDefault`, `migrated`, `matches`)만.
  단축키 편집기는 원래 것(전역 6개 + 스티커 안 제목 변경, 겹침 확인, 입력하는 동안 등록 풀기)을 그대로 쓴다.
- 알람 알림은 `EppNotifications.post(moduleID: "floaty", identifier: <스티커 id>)`, 누르면 `handleNotification`.
- 저장하지 못한 스티커가 있으면 `shouldQuit()`이 끄기 전에 묻는다.
- 잠금 키는 키체인 서비스 `com.eddieee.Floaty` 그대로(나중에 옛 스티커를 가져올 때 같은 키로 풀 수 있게).
- 번역 사전은 `"한국어": "English"` 꼴이다(`scripts/test.sh`가 두 꼴을 다 읽는다).

## Clocky (Modules/Clocky) = 타이머

원본: ../Clocky 0.3.2 (커밋 e1732f4). 바뀐 점:
- `AppDelegate` → `ClockyModule`. 샌드박스 옮기기·받아 둔 dmg 정리·Applications로 옮기라는 안내는 뺐다(Epp에는 해당 없음).
- 메뉴바에 남은 시간은 **보여 줄 것이 있을 때만** 따로 띄운다(타이머가 돌거나 알람이 1시간 안). 없으면 그 항목을 지운다.
- 저장은 `ClockyStorage.defaults`·`folder`(Epp가 준 값). 캘린더 캐시는 `<Epp>/Clocky/Calendars`, 내 소리는 `<Epp>/Clocky/Sounds`.
- 캘린더: Info.plist 설명 문구와 `Resources/Epp.entitlements`(강화 런타임에서 캘린더 읽기)를 본체에 넣었다. 권한 줄은 Epp 일반 → 권한(`.calendar`).
  Mac 캘린더를 켤 때 묻는 흐름(캘린더 탭)은 그대로 둔다.
- 단위 시험은 `Tests/ClockyTests`(Swift Testing). `scripts/test.sh`가 Command Line Tools 경로를 알려 주고 `swift test`로 돌린다.
  옛 GUI 시험(Tests/GUI, gui-test.sh)과 업데이트·샌드박스 시험은 가져오지 않았다.
- 영어 사전은 `ClockySettings.swift` 안 `enum Localization`(`"한국어": "English"` 꼴). **같은 키가 두 번 들어가면 실행 중에 죽는다.**

## Grabby (Modules/Grabby) = 캡처

원본: ../Grabby (커밋 ec8f086). 바뀐 점:
- `AppDelegate` → `GrabbyModule`. 메뉴바 아이콘·시작 안내 창(WelcomeWindow)·업데이트·한 번만 실행은 뺐다. 메뉴는 Epp의 "캡처 ▸".
- `AppPresence`(창이 열리면 일반 앱으로 바꾸기)를 뺐다. Dock·앱 메뉴는 Epp의 "Dock에 아이콘 보이기"를 따른다.
- 앱 메뉴(파일: 캡처 창 열기·저장 ⌘S, 윈도우: 최소화 ⌘M 등)는 `mainMenus()`.
- 테마는 캡처 창(탭 창 `LibraryWindow`, 띄운 캡처 `PinWindow`)에만(`GrabbyTheme`).
- 저장은 `GrabbyStorage.defaults`·`folder`. 탭 보관함 `<Epp>/Grabby/Captures`, 띄운 캡처 `<Epp>/Grabby/Pins`.
  `AppSettings.shared`는 `AppSettings!`라 `let settings: AppSettings = AppSettings.shared`처럼 타입을 적는다.
- 동작 기록(`EventLog`)은 따로 파일을 쓰지 않고 `EppLog.write("캡처", …)`(진단 로그를 켰을 때만).
- 화면 기록 권한이 없을 때 캡처하면 시스템에 묻고 `context.showGettingStarted()`로 캡처 설정(시작하기)을 연다. 권한 줄은 Epp 일반 → 권한.
- 정보 탭의 보관함 크기·캡처 폴더 열기는 저장 탭으로 옮겼다. 점검은 업데이트·AppPresence 묶음을 뺐다.

## 화면 규칙 (모든 기능이 같게)

- **기능 이름은 하는 일로**: 화면에는 앱 이름(Keepy, Peeky) 대신 기능 이름을 쓴다. `EppModuleInfo`의 `nameKo`/`nameEn`.
  클립보드(Keepy) · 메뉴바(Peeky) · 타이머(Clocky) · 스티커(Floaty) · 캡처(Grabby).
  코드 폴더·클래스·id·`storageName`(데이터 폴더, 로그 이름)은 옛 이름 그대로 둔다(바꾸면 저장한 설정과 데이터를 못 찾는다).
  화면 문구에 앱 이름을 쓰지 않는다. 기능이 아니라 앱 전체를 말할 때는 "Epp".
- **권한은 Epp 한 곳에서**: Mac은 권한을 Epp 앱 하나에 준다. 기능은 `static var permissionNeeds`로 무엇을 왜 쓰는지만 알리고,
  Epp 설정 → 일반 → **권한**이 켜진 기능의 필요를 모아 한 줄씩 보여 준다(`EppPermissions.shared`). 기능 설정에는 권한 칸을 두지 않는다.
  시작하기 단계의 권한 줄에는 "권한 열기" 버튼(`context.openPermissions`)을 단다.

본체가 틀을 그리고, 기능은 내용만 넘긴다. 기능이 자기 설정 창·시작 안내 창을 따로 만들지 않는다.

- **기능마다 따로 두지 않는 것 (Epp 일반에 한 번만)**: 로그인 시 실행, Dock, 언어, 권한, 진단 로그(`EppLog`, `~/Library/Logs/<Epp 이름>.log`),
  데이터 폴더(Finder에서 보기), 업데이트, 정보.
  **단축키는 기능마다 자기 단축키 탭에서만** 본다(사용자가 정했다. 일반에 모아 보이지 않는다). 기능은 `globalShortcuts()`로 알리기만 하고,
  켠 다른 기능과 같은 키면 본체가 그 기능의 단축키 탭 위에 경고를 띄운다(`EppSettingsPage`의 `shortcutClashes`).
  기능 설정에는 그 기능에만 뜻이 있는 것만 둔다.
- **로그**: `EppLog.write("<기능 이름>", …)`(진단 로그를 켰을 때만), 오류는 `EppLog.error`(시스템 로그에도). 개인 내용(복사한 글 등)은 적지 않는다.
- **단축키 탭**: 첫 섹션 "전역 단축키"(키 하나를 고르는 건 `EppShortcutRow`, footer는 `EppShortcutText.footer`), 그다음 "<창> 안에서" 키 목록.
- **설정**: `settingsTabs()`가 `[EppSettingsTab]`을 돌려준다. 본체가 `EppSettingsPage`로 그린다:
  머리(아이콘·이름·설명) → 시작하기 상자 → 위쪽 탭 → 고른 탭의 `Form`(`.grouped`).
  - 탭 순서: **일반**(id `general`) · (기능 고유 탭) · **단축키**(id `shortcuts`). 단축키가 없으면 단축키 탭을 빼도 된다.
  - 로그인 시 실행, 언어, Dock, 업데이트, 정보는 본체 일반 쪽에만 둔다.
  - 탭마다 `keywords`에 그 탭의 설정 이름(`L("…")` 그대로)을 넣는다. 설정 창 왼쪽 위 **설정 검색**이 이걸로 찾는다.
  - 창 도구 막대(`.searchable(placement: .toolbar)`)를 쓰지 않는다. 다른 쪽까지 모양이 바뀐다. 목록을 거르는 검색은 그 목록 바로 위에 둔다.
- **시작하기**: `makeGettingStarted()`가 `EppStepList`(3단계 안팎 + 짧은 footer)를 돌려준다. 끝낸 단계는 체크로 바뀐다.
  처음 켤 때 본체가 그 기능 설정을 연다. 닫으면 숨고, 메뉴 "시작 안내"(본체가 붙임)나 `context.showGettingStarted()`로 다시 연다.
- **메뉴**: `fillMenu`에는 주 동작(열기) → 고유 항목만. 본체가 끝에 "시작 안내", "<이름> 설정…"을 붙인다.
- **앱 메뉴**(화면 맨 위 왼쪽): 기능은 `mainMenus()`로 `EppMainMenu(.file/.edit/.format/.window, 메뉴)`만 넘긴다.
  본체가 Epp · 파일 · 편집 · 서식 · 윈도우 순서로 합치고, 같은 동작·같은 키는 한 번만 넣는다. `NSApp.mainMenu`를 직접 바꾸지 않는다.
- **알림**: `EppNotifications.post`로 보내고 `handleNotification(identifier:)`로 받는다. 알림 센터 처리기는 본체 하나다.
  알림을 쓰면 `permissionNeeds`에 `.notifications`를 넣는다.
- **끝내기 전 확인**: 저장하지 못한 내용이 있으면 `shouldQuit()`에서 묻는다. `stop()`에서는 저장하고 창·타이머·관찰을 모두 거둔다.

## 남은 일

- [ ] 캡처: 실제 캡처(화면 기록 권한 허용 뒤)·탭 창·띄운 캡처를 확인
- [ ] 타이머: 남은 시간 메뉴바 항목, 캘린더 권한 묻기를 실제로 확인
- [ ] 스티커: 앱 메뉴 합치기(⌘D·서식 등)와 알람 알림을 실제로 눌러 확인
- [ ] Peeky를 실제로 켜서 확인(권한, 그룹 아이콘, 숨기기·정리, 끄고 켤 때 아이콘이 깨끗이 사라지는지)
- [ ] 첫 릴리스(v0.1.0): 저장소 공개, `./scripts/release.sh` (노트 `docs/releases/v0.1.0.md`는 씀)
- [ ] 옛 단독 앱 정리: 릴리스 뒤 **사용자가 따로 말하면** 옛 저장소 5개·설치된 앱·코드 폴더를 지운다(그전에는 건드리지 않는다).
  앞으로는 Epp 하나로 관리한다. 옛 앱 데이터 가져오기는 만들지 않는다(사용자 혼자 쓰므로 필요 없다고 했다. 2026-11-23).
- [ ] `../mac-app/scripts/sync-shared.sh`가 Epp에도 AppUpdater를 복사하게 하기(지금은 손으로 복사)
