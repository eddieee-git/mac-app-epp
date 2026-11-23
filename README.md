<p align="center"><img src="docs/images/icon.png" width="96" alt="Epp icon"></p>

<h1 align="center">Epp</h1>

<p align="center">Mac을 편하게 쓰는 작은 기능 모음 (Eddie's app)<br>메뉴바 아이콘 하나에서 필요한 기능만 켜서 써요.</p>

> 아직 만드는 중이에요. 배포하지 않았고, 기존 단독 앱(Clocky, Floaty, Grabby, Keepy, Peeky)은 그대로 쓰면 돼요.
> 같은 기능의 단독 앱과 Epp 기능을 함께 켜지 마세요(단축키와 메뉴바 아이콘이 겹쳐요).

## 들어 있는 기능

| 기능 | 하는 일 | 상태 |
|---|---|---|
| **클립보드** (옛 Keepy) | 복사한 내용을 모아 두고 다시 붙여 넣는 클립보드 기록 | 옮김 |
| **메뉴바** (옛 Peeky) | 노치에 가려진 메뉴바 아이콘 꺼내 보기, 고른 아이콘 메뉴바에서 숨기기 | 옮김 |
| **타이머** (옛 Clocky) | 넘김시계 타이머·알람과 일정 알림 | 옮김 |
| **스티커** (옛 Floaty) | 다른 창 위에 띄워 두는 스티커 메모 | 옮김 |
| **캡처** (옛 Grabby) | 찍고, 그리고, 바로 붙여 넣는 화면 캡처 | 옮김 |

## 쓰는 방법

- 메뉴바의 Epp 아이콘(네모 네 개)을 누르면 켠 기능이 하나씩 메뉴로 나와요.
- 평소에는 Dock에 보이지 않아요. 설정에서 **Dock에 아이콘 보이기**를 켜면 일반 앱처럼 Dock에도 나와요.
- 처음에는 모든 기능이 꺼져 있어요. **설정 → 일반 → 기능**에서 쓸 기능만 켜요.
- 끈 기능은 아무 일도 하지 않아요. 단축키도 등록하지 않고, 클립보드도 보지 않아요.
- 메뉴바 기능은 켜면 그룹마다 바 아이콘이 메뉴바에 따로 생겨요(그게 하는 일이라서). 같은 동작은 Epp 메뉴의 **메뉴바 ▸**에도 있어요.
- 설정 창 왼쪽 위 **설정 검색**으로 모든 기능의 설정을 찾을 수 있어요. 기능마다 맨 위에 **시작하기**가 있고, 메뉴의 **시작 안내**로 다시 열어요.
- 다른 도구(단축어 등)에서 주소로 열 수 있어요.
  - 클립보드: `epp://keepy/show`(기록 창)
  - 메뉴바: `epp://peeky/open`(아이콘 바), `epp://peeky/arrange`(다시 정리)
  - 스티커: `epp://floaty/new`(새 스티커), `epp://floaty/manager`(스티커 관리), `epp://floaty/toggle`(모두 보이기·숨기기)
  - 타이머: `epp://clocky/show`(시계 창), `epp://clocky/list`(전체 목록), `epp://clocky/toggle`(시작·일시정지)
  - 캡처: `epp://grabby/area`(영역 캡처), `epp://grabby/library`(캡처 창)

  웹페이지도 이 주소를 열 수 있어서, 직접 고르지 않아도 되는 화면 전체 캡처는 주소로 열지 않아요. 10초에 5번이 넘게 오면 무시해요.
- 클립보드 기록은 암호화해서 저장해요(키는 키체인). 고정하지 않은 기록은 기본 30일이 지나면 지워요(클립보드 설정 → 일반에서 바꿔요).

## 설정

| 항목 | 설명 |
|---|---|
| 기능 | 기능마다 켜기/끄기 (기본 모두 끔) |
| 로그인 시 실행 | Mac에 로그인하면 Epp를 켜요 (기본 끔) |
| Dock에 아이콘 보이기 | Dock과 메뉴 막대 왼쪽에 Epp를 보여 줘요. Dock 아이콘을 오른쪽 클릭하면 기능 메뉴가 나와요 (기본 끔) |
| 언어 | 시스템 / 한국어 / English (기본 시스템). 바꾸면 Epp를 다시 열어야 해요 |
| 업데이트 | 새 버전 자동으로 확인(기본 켬, 하루 한 번), 자동으로 설치(기본 켬, Epp를 쓰지 않을 때) |
| 기능별 설정 | 왼쪽 목록에서 기능을 고르면 그 기능의 설정이 나와요 |

## 데이터는 어디에

- 기능마다 따로 저장해요: `~/Library/Application Support/Epp/<기능 이름>/`
- 기존 단독 앱의 데이터(예: `~/Library/Application Support/Keepy`)는 읽지도 바꾸지도 않아요.

## 권한

- 권한은 **설정 → 일반 → 권한** 한 곳에서 봐요. 켠 기능이 어떤 권한을 왜 쓰는지 함께 나와요.
- 손쉬운 사용: 클립보드 바로 붙여 넣기, 메뉴바(필수). 화면 기록(선택): 메뉴바가 실제 아이콘 모양을 보여 줄 때. 켠 뒤 Epp를 다시 열어야 해요.
- 권한은 Epp 하나에 주는 거라 기존 단독 앱에 준 권한과는 따로예요.

## 업데이트

하루 한 번 GitHub에 최신 버전 번호만 물어봐요. 새 버전이 있으면 Epp를 쓰지 않을 때 받아서, 서명이 맞는지 확인한 뒤 바꿔 넣고 다시 켜요. 복사한 내용 같은 개인 내용은 어디에도 보내지 않아요.

## 알려진 제한

- Apple 실리콘 Mac, macOS 14 이상.
- 임시 서명이라 처음 열 때 Gatekeeper 경고가 떠요.
- 자동 업데이트는 저장소를 공개하고 첫 릴리스를 낸 뒤부터 동작해요.
- 같은 기능의 단독 앱과 함께 켜면 단축키가 겹쳐요. 둘 중 하나만 켜 두세요.

## English

Epp (Eddie's app) gathers small Mac menu bar tools under one icon. Turn on only the features you want in Settings → General → Features; features that are off do nothing. Work in progress: Keepy (clipboard history) and Peeky (menu bar icons behind the notch) have been moved in so far.
