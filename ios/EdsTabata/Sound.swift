import Foundation
import AVFoundation

/// Plays the beeps *on top of* Spotify (or any other music) and keeps the app
/// alive in the background while a workout runs.
final class SoundPlayer {
    var settings = SoundSettings()

    private let engine = AVAudioEngine()
    private let fx = AVAudioPlayerNode()
    private let keepAlive = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let speech = AVSpeechSynthesizer()
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var workoutActive = false
    private var idleToken = 0

    init() {
        engine.attach(fx)
        engine.attach(keepAlive)
        engine.connect(fx, to: engine.mainMixerNode, format: format)
        engine.connect(keepAlive, to: engine.mainMixerNode, format: format)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended,
                  self.workoutActive else { return }
            self.activate()
            self.startEngine()
            self.startKeepAlive()
        }
    }

    /// .playback + .mixWithOthers: works with the mute switch on, mixes with Spotify.
    private func activate() {
        let s = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if settings.duck && workoutActive { options.insert(.duckOthers) }
        try? s.setCategory(.playback, mode: .default, options: options)
        try? s.setActive(true)
    }

    private func startEngine() {
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    private func startKeepAlive() {
        guard engine.isRunning, !keepAlive.isPlaying else { return }
        let frames = AVAudioFrameCount(format.sampleRate / 2)
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        silence.frameLength = frames // zero-filled
        keepAlive.scheduleBuffer(silence, at: nil, options: .loops, completionHandler: nil)
        keepAlive.play()
    }

    /// Workout started: stay alive in the background.
    func begin() {
        workoutActive = true
        idleToken += 1
        activate()
        startEngine()
        startKeepAlive()
    }

    /// Workout paused/finished: release audio after the last sound has played.
    func end() {
        workoutActive = false
        scheduleIdle(after: 4)
    }

    private func scheduleIdle(after seconds: Double) {
        idleToken += 1
        let token = idleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, token == self.idleToken, !self.workoutActive else { return }
            self.keepAlive.stop()
            self.engine.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func play(_ choice: SoundChoice, _ kind: SoundKind, word: String) {
        guard choice != .off else { return }
        if !workoutActive {
            activate()
            scheduleIdle(after: 4)
        }
        if choice == .voice {
            speak(word)
            return
        }
        startEngine()
        let key = "\(choice.rawValue)-\(kind)"
        if cache[key] == nil { cache[key] = Synth.render(choice, kind, format: format) }
        guard let buf = cache[key] else { return }
        fx.volume = Float(settings.volume)
        guard engine.isRunning else { return }
        fx.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !fx.isPlaying { fx.play() }
    }

    private func speak(_ word: String) {
        let u = AVSpeechUtterance(string: word.lowercased())
        u.voice = AVSpeechSynthesisVoice(language: "nl-NL")
        u.rate = 0.55
        u.volume = Float(settings.volume)
        speech.stopSpeaking(at: .immediate)
        speech.speak(u)
    }
}

// MARK: - Sound synthesis (no audio files needed)

enum Synth {
    static func render(_ c: SoundChoice, _ k: SoundKind, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var m = Mixer(sampleRate: format.sampleRate)
        let short = k == .count
        switch c {
        case .off, .voice:
            return nil
        case .beep:
            m.tone(short ? 880 : 1320, short ? 0.12 : 0.45, wave: .square, vol: 0.5)
        case .high:
            m.tone(short ? 1760 : 2093, short ? 0.12 : 0.4, vol: 0.6)
        case .double:
            m.tone(1320, 0.1, wave: .square, vol: 0.5)
            m.tone(1320, 0.1, wave: .square, vol: 0.5, at: 0.15)
            if !short { m.tone(1760, 0.3, wave: .square, vol: 0.5, at: 0.3) }
        case .click:
            m.noise(0.04, vol: 0.9)
            if !short { m.noise(0.04, at: 0.12, vol: 0.9) }
        case .bell:
            m.bell(short ? 1200 : 900, len: short ? 0.5 : 1.6)
        case .boxing:
            if short {
                m.bell(1500, len: 0.4)
            } else {
                for i in 0..<3 { m.bell(1500, at: Double(i) * 0.22, len: 0.9, vol: 0.45) }
            }
        case .whistle:
            m.tone(2700, short ? 0.18 : 0.7, vol: 0.4, attack: 0.02, vibratoRate: 28, vibratoDepth: 180)
        case .gong:
            for (f, a) in [(110.0, 1.0), (164.0, 0.6), (221.0, 0.5), (331.0, 0.3), (442.0, 0.2)] {
                m.tone(f, short ? 0.8 : 3.2, vol: 0.45 * a, attack: 0.004)
            }
        case .horn:
            m.tone(233, short ? 0.25 : 0.9, wave: .saw, vol: 0.12, attack: 0.03)
            m.tone(233.6, short ? 0.25 : 0.9, wave: .square, vol: 0.12, attack: 0.03)
            m.tone(466, short ? 0.25 : 0.9, wave: .saw, vol: 0.06, attack: 0.03)
        }
        return m.buffer(format: format)
    }
}

struct Mixer {
    enum Wave { case sine, square, saw }

    let sampleRate: Double
    var samples: [Float] = []

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    private mutating func ensure(_ n: Int) {
        if samples.count < n { samples += [Float](repeating: 0, count: n - samples.count) }
    }

    mutating func tone(_ f: Double, _ dur: Double, wave: Wave = .sine, vol: Double = 0.5, at: Double = 0,
                       attack: Double = 0.005, vibratoRate: Double = 0, vibratoDepth: Double = 0) {
        let start = Int(at * sampleRate)
        let n = Int(dur * sampleRate)
        ensure(start + n)
        let low = 0.0001
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let freq = f + vibratoDepth * sin(2 * Double.pi * vibratoRate * t)
            phase += freq / sampleRate
            phase -= phase.rounded(.down)
            let x: Double
            switch wave {
            case .sine: x = sin(2 * Double.pi * phase)
            case .square: x = phase < 0.5 ? 1 : -1
            case .saw: x = 2 * phase - 1
            }
            let env: Double
            if t < attack {
                env = low * pow(vol / low, t / attack)
            } else {
                env = vol * pow(low / vol, (t - attack) / max(0.001, dur - attack))
            }
            samples[start + i] += Float(x * env)
        }
    }

    mutating func bell(_ f: Double, at: Double = 0, len: Double = 1.2, vol: Double = 0.5) {
        for (mult, amp) in [(1.0, 1.0), (2.76, 0.45), (5.4, 0.25), (8.93, 0.12)] {
            tone(f * mult, len / pow(mult, 0.4), vol: vol * amp, at: at, attack: 0.002)
        }
    }

    mutating func noise(_ dur: Double, at: Double = 0, vol: Double = 0.6) {
        let start = Int(at * sampleRate)
        let n = Int(dur * sampleRate)
        ensure(start + n)
        var prev = 0.0
        for i in 0..<n {
            let r = Double.random(in: -1...1)
            let hp = r - prev // crude high-pass
            prev = r
            let env = pow(1 - Double(i) / Double(n), 3)
            samples[start + i] += Float(hp * 0.5 * vol * env)
        }
    }

    /// Normalised so every sound is loud enough to hear over music.
    func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let tail = Int(0.03 * sampleRate)
        let count = samples.count + tail
        guard count > 0,
              let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let ch = b.floatChannelData?[0] else { return nil }
        b.frameLength = AVAudioFrameCount(count)
        let peak = samples.map { abs($0) }.max() ?? 1
        let gain: Float = peak > 0 ? 0.9 / peak : 1
        for i in 0..<count { ch[i] = i < samples.count ? samples[i] * gain : 0 }
        return b
    }
}
