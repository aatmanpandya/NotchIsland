import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Opt-in live visualizer: listens to what the Mac is playing and turns it into four frequency
/// bands (bass to treble) for the bars. macOS asks for "System Audio Recording" permission the
/// first time. Audio is analyzed in memory and never stored.
final class LiveSpectrum: ObservableObject {
    static let shared = LiveSpectrum()

    /// Levels 0...1, or nil when the bars should use their decorative motion instead.
    @Published private(set) var bands: [Float]?

    private var engine: AnyObject?

    private var isPlaying = false

    /// Starts listening the first time something plays with the visualizer on, then keeps the
    /// tap open until it's switched off. Starting a tap is what triggers macOS's permission
    /// prompt, so this asks at most once per launch instead of on every play.
    func update(enabled: Bool, isPlaying: Bool) {
        self.isPlaying = isPlaying
        guard #available(macOS 14.2, *) else { return }
        if enabled, isPlaying, engine == nil {
            let tap = SystemAudioTap { [weak self] levels in
                DispatchQueue.main.async {
                    guard let self, self.isPlaying else { return }
                    self.bands = levels
                }
            }
            if tap.start() { engine = tap }
        } else if !enabled, let tap = engine as? SystemAudioTap {
            tap.stop()
            engine = nil
        }
        // While nothing plays (or it's off), the bars go back to their decorative motion.
        if !enabled || !isPlaying { bands = nil }
    }
}

@available(macOS 14.2, *)
private final class SystemAudioTap {
    private let onBands: ([Float]) -> Void
    private let queue = DispatchQueue(label: "notchisland.spectrum")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    // Analysis state, touched only on `queue`.
    private let log2n: vDSP_Length = 10
    private var fftSize: Int { 1 << Int(log2n) }
    private let fftSetup: FFTSetup?
    private let window: [Float]
    private var samples: [Float] = []
    private var smoothed = [Float](repeating: 0, count: 4)
    /// Per-band loudest recent level, decaying slowly: automatic gain, so quiet and loud
    /// songs both fill the bars.
    private var peaks = [Float](repeating: 1e-3, count: 4)
    private var sampleRate: Double = 48_000
    private var lastSent = Date.distantPast

    /// Band edges in Hz: bass, low mids, high mids, treble.
    private let edges: [Double] = [40, 160, 600, 2_500, 9_000]

    init(onBands: @escaping ([Float]) -> Void) {
        self.onBands = onBands
        fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 1 << 10, isHalfWindow: false)
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    func start() -> Bool {
        // Tap everything the Mac plays, without muting it.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return false }

        let output = VolumeService.defaultOutputDevice()
        guard let outputUID = Self.uid(of: output) else { stop(); return false }
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchIsland Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID) == noErr else {
            stop()
            return false
        }
        sampleRate = Self.nominalSampleRate(of: aggregateID) ?? 48_000

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.receive(input)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Analysis

    /// Keeps the first channel of the tap's float samples and analyzes each full window.
    private func receive(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        let channels = max(1, Int(buffer.mNumberChannels))
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let floats = data.assumingMemoryBound(to: Float.self)
        for index in stride(from: 0, to: count, by: channels) { samples.append(floats[index]) }
        while samples.count >= fftSize {
            analyze(Array(samples.prefix(fftSize)))
            samples.removeFirst(fftSize / 2)
        }
    }

    private func analyze(_ frame: [Float]) {
        guard let fftSetup else { return }
        let half = fftSize / 2
        let windowed = vDSP.multiply(frame, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let binWidth = sampleRate / Double(fftSize)
        for band in 0..<4 {
            let low = max(1, Int(edges[band] / binWidth))
            let high = min(half - 1, max(low + 1, Int(edges[band + 1] / binWidth)))
            let energy = vDSP.mean(magnitudes[low..<high])
            peaks[band] = max(peaks[band] * 0.997, energy)
            let level = peaks[band] > 1e-3 ? min(1, energy / peaks[band]) : 0
            // Rise fast, fall slowly, like a real level meter.
            let rate: Float = level > smoothed[band] ? 0.6 : 0.18
            smoothed[band] += (level - smoothed[band]) * rate
        }

        // About 30 updates a second is plenty for the bars.
        let now = Date()
        if now.timeIntervalSince(lastSent) > 1.0 / 30 {
            lastSent = now
            onBands(smoothed)
        }
    }

    // MARK: - Core Audio helpers

    private static func uid(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func nominalSampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr ? rate : nil
    }
}
