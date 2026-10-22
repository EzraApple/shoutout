import CoreAudio
import Foundation

var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var device: AudioDeviceID = 0
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
if let value = CommandLine.arguments.dropFirst().first, let requested = AudioDeviceID(value) {
    device = requested
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                           0, nil, size, &device)
    if status != noErr { exit(1) }
}
let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       0, nil, &size, &device)
guard status == noErr else { exit(1) }
print(device)
