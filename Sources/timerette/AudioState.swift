import CoreAudio
import AudioToolbox

// MARK: - Output audio state

enum AudioState {
	// True when the default output device is muted or its main volume is 0.
	// The chime would be inaudible, so the AlertChip must show instead.
	// Any query failure reports audible (chime plays, no chip).
	static func outputIsEffectivelySilent() -> Bool {
		var deviceID = AudioObjectID(kAudioObjectUnknown)
		var size = UInt32(MemoryLayout<AudioObjectID>.size)
		var addr = AudioObjectPropertyAddress(
			mSelector: kAudioHardwarePropertyDefaultOutputDevice,
			mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain
		)
		guard AudioObjectGetPropertyData(
			AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
			deviceID != kAudioObjectUnknown
		else { return false }

		// Device mute
		addr = AudioObjectPropertyAddress(
			mSelector: kAudioDevicePropertyMute,
			mScope: kAudioDevicePropertyScopeOutput,
			mElement: kAudioObjectPropertyElementMain
		)
		if AudioObjectHasProperty(deviceID, &addr) {
			var muted: UInt32 = 0
			size = UInt32(MemoryLayout<UInt32>.size)
			if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted) == noErr, muted == 1 {
				return true
			}
		}

		// Virtual main volume at zero
		addr = AudioObjectPropertyAddress(
			mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
			mScope: kAudioDevicePropertyScopeOutput,
			mElement: kAudioObjectPropertyElementMain
		)
		if AudioObjectHasProperty(deviceID, &addr) {
			var volume: Float32 = 1
			size = UInt32(MemoryLayout<Float32>.size)
			if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &volume) == noErr, volume <= 0.001 {
				return true
			}
		}
		return false
	}
}
