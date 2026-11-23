import AppKit
import EppKit
import Vision

/// 캡처했다는 표시: 찍은 영역을 잠깐 하얗게 반짝이고, 설정에 따라 셔터 소리를 낸다.
@MainActor
enum CaptureFeedback {
    private static var flashes: [NSWindow] = []
    private static let sound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    /// `rect`는 전역 좌표(왼쪽 아래 원점).
    static func flash(_ rect: CGRect) {
        if AppSettings.shared.captureSound {
            sound?.stop()
            sound?.play()
        }
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.55)
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.orderFrontRegardless()
        flashes.append(window)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            flashes.removeAll { $0 === window }
        })
    }
}

/// 이미지 속 글자 인식. 한국어와 영어를 함께 읽는다.
enum TextRecognizer {
    /// 시간이 걸리므로 백그라운드에서 돌린다.
    /// 사용자가 누른 글자 복사는 바로 결과를 기다리므로 높은 우선순위로,
    /// 검색용으로 뒤에서 하는 인식은 `.utility`로 돌려 팬·배터리 부담을 줄인다.
    static func recognize(_ image: CGImage, priority: TaskPriority = .userInitiated) async -> String {
        await Task.detached(priority: priority) { recognizeNow(image) }.value
    }

    /// 지금 있는 스레드에서 바로 인식한다(이미 뒤에서 도는 작업 안에서 쓸 때).
    nonisolated static func recognizeNow(_ image: CGImage) -> String {
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US"]
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
    }
}
