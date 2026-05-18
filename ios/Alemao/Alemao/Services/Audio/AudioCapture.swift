import AVFoundation
import Foundation

/// Captura áudio do microfone via AVAudioEngine, converte para PCM 16-bit @ 16 kHz mono,
/// e entrega chunks via callback (typicamente 100 ms por chunk).
///
/// Uso:
/// ```
/// let cap = AudioCapture()
/// cap.onChunk = { data in /* envia pra Gemini Live */ }
/// try await cap.start()
/// ...
/// cap.stop()
/// ```
final class AudioCapture {
    let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let chunkFrames: AVAudioFrameCount = 1600  // 100 ms @ 16 kHz

    /// Chamado em uma thread de áudio. Cuidado com main-actor.
    var onChunk: ((Data) -> Void)?

    init() {
        // PCM 16-bit, 16 kHz, mono, interleaved
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
    }

    func start() async throws {
        try await requestPermission()
        try configureSession()
        try installTap()
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Internal

    @MainActor
    private func requestPermission() async throws {
        let granted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { ok in cont.resume(returning: ok) }
        }
        if !granted {
            throw NSError(
                domain: "AudioCapture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Permissão de microfone negada."]
            )
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    private func installTap() throws {
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(
                domain: "AudioCapture", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Falha ao criar AVAudioConverter"]
            )
        }
        self.converter = converter

        let bufferSize: AVAudioFrameCount = 4096
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] inputBuffer, _ in
            self?.process(inputBuffer)
        }
    }

    private func process(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        // Estima frames de saída baseado na razão de sample rates
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 1)
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outFrameCapacity
        ) else { return }

        var error: NSError?
        var supplied = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return inputBuffer
        }
        if let error {
            print("AudioCapture converter error: \(error)")
            return
        }
        guard let int16 = outBuffer.int16ChannelData else { return }
        let frameLength = Int(outBuffer.frameLength)
        let data = Data(bytes: int16[0], count: frameLength * MemoryLayout<Int16>.size)
        if !data.isEmpty {
            onChunk?(data)
        }
    }
}
