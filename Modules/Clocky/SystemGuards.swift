import AudioToolbox
import EppKit
import CoreAudio
import Foundation
import IOKit.pwr_mgt

/// 곧 울릴 것이 있으면 Mac이 저절로 잠들지 않게 막는다. 화면은 꺼져도 된다.
/// 덮개를 닫거나 사용자가 직접 잠들게 하는 것은 막지 않는다(막을 수도 없다).
final class SleepGuard {
    private var assertion: IOPMAssertionID = 0
    private(set) var isHolding = false

    func update(needsAwake: Bool) {
        if needsAwake == isHolding { return }
        if needsAwake {
            var id: IOPMAssertionID = 0
            let reason = "Epp: 곧 울릴 타이머나 알람이 있어요" as CFString
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                assertion = id
                isHolding = true
            }
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isHolding = false
        }
    }

    deinit {
        if isHolding { IOPMAssertionRelease(assertion) }
    }
}

/// Mac의 기본 출력 장치가 음소거이거나 소리 크기가 0인지. 알 수 없으면 false(경고하지 않는다).
enum SystemVolume {
    static var isSilent: Bool {
        guard let device = defaultOutputDevice else { return false }
        if let muted = value(UInt32.self, device, kAudioDevicePropertyMute), muted != 0 { return true }
        // 장치 전체 소리 크기. 없으면 첫 채널을 본다.
        if let volume = value(Float32.self, device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) { return volume <= 0.001 }
        if let volume = value(Float32.self, device, kAudioDevicePropertyVolumeScalar, element: 1) { return volume <= 0.001 }
        return false
    }

    private static var defaultOutputDevice: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func value<T>(_ type: T.Type, _ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }
}
