import EppKit
import SwiftUI

/// 설정 맨 위 시작하기 상자. 끝낸 단계는 체크로 바뀐다.
struct FloatyGettingStarted: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: AppSettings

    private func keys(_ action: HotKeyAction) -> String {
        settings.hotKeys[action.rawValue]?.displayText ?? L("메뉴")
    }

    var body: some View {
        EppStepList([
            .init(L("%@로 새 스티커 만들기", keys(.newNote)), done: store.activeNotes.count >= 2),
            .init(L("메뉴의 스티커 관리에서 숨긴 스티커까지 모두 보기"), done: settings.hasOpenedManager),
            .init(L("%@로 스티커를 모두 숨기고 다시 보이기", keys(.toggleAll)), done: settings.hasToggledAll),
        ], footer: L("스티커 오른쪽 위 단추로 항상 위, 색, 알람, 잠그기를 정해요. 지운 스티커는 휴지통에서 되살릴 수 있어요."))
    }
}
