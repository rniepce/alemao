import AVFoundation
import Foundation

/// Player streaming de chunks PCM 16-bit recebidos do Gemini Live (@24 kHz mono).
/// Usa AVAudioEngine + AVAudioPlayerNode.
final class AudioPlayer {
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    let sourceFormat: AVAudioFormat
    private var isStarted: Bool = false

    init(sampleRate: Double = 24_000) {
        self.sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!
    }

    func start() throws {
        guard !isStarted else { return }
        engine.attach(playerNode)
        // Toca direto no main mixer; AVAudioEngine faz o resampling pro sample rate de saída.
        engine.connect(playerNode, to: engine.mainMixerNode, format: sourceFormat)
        engine.prepare()
        try engine.start()
        playerNode.play()
        isStarted = true
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isStarted = false
    }

    func enqueue(pcm16: Data) {
        guard isStarted else { return }
        let frameCount = AVAudioFrameCount(pcm16.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        pcm16.withUnsafeBytes { rawPtr in
            guard let src = rawPtr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            guard let dst = buffer.int16ChannelData?[0] else { return }
            dst.update(from: src, count: Int(frameCount))
        }
        playerNode.scheduleBuffer(buffer)
    }
}
