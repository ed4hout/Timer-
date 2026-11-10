import SwiftUI
import UIKit
import Combine

final class AppModel: ObservableObject {
    let board = Board()
    let sound = SoundPlayer()

    // MARK: Settings (saved automatically)

    @Published var config: WorkoutConfig {
        didSet { Store.save("cfg", config); if oldValue != config { rebuild(); reset() } }
    }
    @Published var looks: Looks {
        didSet { Store.save("looks", looks); lastKey = ""; gifSeg = -1; refreshBoard() }
    }
    @Published var favorites: [Favorite] {
        didSet { Store.save("favs", favorites) }
    }
    @Published var soundSettings: SoundSettings {
        didSet { Store.save("snd", soundSettings); sound.settings = soundSettings }
    }
    @Published var keepAwake: Bool {
        didSet { UserDefaults.standard.set(keepAwake, forKey: "awake"); updateIdleTimer() }
    }
    @Published var brightness: Double {
        didSet { UserDefaults.standard.set(brightness, forKey: "bright") }
    }
    /// Seconds the board animation is started ahead, to make up for Bluetooth/board delay.
    @Published var boardCorrection: Double {
        didSet { UserDefaults.standard.set(boardCorrection, forKey: "corr") }
    }
    @Published var message = "LETS GO!"
    @Published var rotation = 0
    @Published var toast: String?

    // MARK: Timer state

    @Published private(set) var running = false
    @Published private(set) var preview = Frame()
    @Published private(set) var tick = 0

    private(set) var segments: [Segment] = []
    private var cum: [Double] = []
    private(set) var total: Double = 0
    private var t0 = Date()
    private var pausedE: Double = 0
    private var timer: Timer?
    private var lastIdx = -1
    private var lastKey = ""
    private var lastTick = Date()
    private var catching = false
    private var toastID = UUID()
    private var gifSeg = -1
    private var gifEnd: (idx: Int, rem: Int)?
    private var observers: [NSObjectProtocol] = []

    init() {
        config = Store.load("cfg", WorkoutConfig())
        looks = Store.load("looks", Looks())
        favorites = Store.load("favs", [Favorite]())
        soundSettings = Store.load("snd", SoundSettings())
        keepAwake = UserDefaults.standard.object(forKey: "awake") as? Bool ?? true
        brightness = UserDefaults.standard.object(forKey: "bright") as? Double ?? 70
        boardCorrection = UserDefaults.standard.object(forKey: "corr") as? Double ?? 1.5

        sound.settings = soundSettings
        board.brightness = Int(brightness)
        rebuild()
        restoreRun()
        board.onConnect = { [weak self] in
            self?.lastKey = ""
            self?.gifSeg = -1
            self?.refreshBoard()
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.lastTick = .distantPast // don't fire a burst of beeps after coming back
                self?.updateIdleTimer()
            })
    }

    // MARK: Engine (wall-clock based, so it is always right after the app was away)

    private func rebuild() {
        segments = buildSegments(config)
        cum = []
        var a = 0.0
        for s in segments { cum.append(a); a += Double(s.dur) }
        total = a
    }

    var elapsed: Double { running ? Date().timeIntervalSince(t0) : pausedE }

    private func position(_ e: Double) -> (idx: Int, el: Double) {
        guard !segments.isEmpty else { return (0, 0) }
        if e >= total { return (segments.count - 1, Double(segments[segments.count - 1].dur)) }
        var i = 0
        while i < segments.count - 1 && e >= cum[i + 1] { i += 1 }
        return (i, e - cum[i])
    }

    var display: Display {
        let e = elapsed
        let finished = total > 0 && e >= total
        let p = position(e)
        let seg: Segment? = segments.isEmpty ? nil : segments[p.idx]
        let phase: Phase = finished ? .done : (seg?.phase ?? .prep)
        let dur = Double(seg?.dur ?? 0)
        let remain = finished ? 0 : max(0, dur - p.el)
        let frac = (finished || dur == 0) ? 0 : 1 - remain / dur
        let idle = !running && pausedE == 0
        return Display(phase: phase, idle: idle, paused: !running && !finished && !idle, finished: finished,
                       remain: remain, sec: Int(ceil(remain - 1e-9)), frac: frac,
                       round: finished ? config.rounds : (seg?.round ?? 0),
                       set: finished ? config.sets : (seg?.set ?? 1),
                       left: max(0, total - e))
    }

    func toggle() { running ? pause() : start() }

    func start(cueNow: Bool = false) {
        guard !running, total > 0 else { return }
        if pausedE >= total { reset() }
        let p = position(pausedE)
        let seg = segments[p.idx]
        let rem = max(1, Int(ceil(Double(seg.dur) - p.el - 1e-6)))
        pausedE = cum[p.idx] + Double(seg.dur - rem) // snap to whole seconds
        t0 = Date().addingTimeInterval(-pausedE)
        running = true
        sound.begin()
        if pausedE == 0 || cueNow { cue(seg.phase) }
        lastIdx = p.idx
        lastTick = Date()
        lastKey = ""
        gifSeg = -1
        startTimer()
        saveRun()
        updateIdleTimer()
        step()
    }

    func pause() {
        guard running else { return }
        pausedE = elapsed
        running = false
        timer?.invalidate()
        saveRun()
        lastKey = ""
        refreshBoard()
        sound.end()
        updateIdleTimer()
        tick &+= 1
    }

    func skip() {
        let wasRunning = running
        if running {
            pausedE = elapsed
            running = false
            timer?.invalidate()
        }
        guard pausedE < total else { return }
        let p = position(pausedE)
        pausedE = cum[p.idx] + Double(segments[p.idx].dur)
        if pausedE >= total {
            finish(silent: !wasRunning)
        } else if wasRunning {
            start(cueNow: true)
        } else {
            saveRun()
            lastKey = ""
            refreshBoard()
            tick &+= 1
        }
    }

    func reset() {
        running = false
        timer?.invalidate()
        pausedE = 0
        lastIdx = -1
        lastKey = ""
        Store.remove("run")
        sound.end()
        updateIdleTimer()
        refreshBoard()
        tick &+= 1
    }

    private func finish(silent: Bool) {
        running = false
        timer?.invalidate()
        pausedE = total
        Store.remove("run")
        if !silent { sound.play(soundSettings.done, .done, word: looks.label(.done)) }
        sound.end()
        updateIdleTimer()
        lastKey = ""
        refreshBoard()
        tick &+= 1
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        guard running else { return }
        let now = Date()
        catching = now.timeIntervalSince(lastTick) > 1.5
        lastTick = now
        let e = elapsed
        if e >= total { finish(silent: catching); return }
        let p = position(e)
        if p.idx != lastIdx {
            if !catching { cue(segments[p.idx].phase) }
            lastIdx = p.idx
        }
        let d = display
        let key = "\(p.idx):\(d.sec)"
        if key != lastKey {
            if !catching && d.sec >= 1 && d.sec <= 3 && lastKey != "" {
                sound.play(soundSettings.count, .count, word: "\(d.sec)")
            }
            lastKey = key
            refreshBoard(d)
        }
        tick &+= 1
    }

    private func cue(_ phase: Phase) {
        switch phase {
        case .work: sound.play(soundSettings.work, .phase, word: looks.label(.work))
        case .rest, .setrest: sound.play(soundSettings.rest, .phase, word: looks.label(LookKey(phase)))
        case .prep: sound.play(soundSettings.count, .count, word: looks.label(.prep))
        case .done: sound.play(soundSettings.done, .done, word: looks.label(.done))
        }
    }

    private func refreshBoard(_ d: Display? = nil) {
        let dd = d ?? display
        let f = BoardArt.timer(dd, cfg: config, looks: looks)
        preview = f
        if running {
            // One animation per phase: the board counts the seconds itself, so it never flashes.
            let p = position(elapsed)
            if p.idx != gifSeg {
                gifSeg = p.idx
                board.play { [weak self] in self?.segmentGif() }
            } else if let ge = gifEnd, ge.idx == p.idx, dd.remain <= Double(ge.rem) + 3 {
                gifEnd = nil
                board.play { [weak self] in self?.segmentGif() }
            }
        } else {
            gifSeg = -1
            gifEnd = nil
            board.show(f)
        }
    }

    /// Built right before sending, so it starts on the second the board will actually show it.
    private func segmentGif() -> [UInt8]? {
        guard running else { return nil }
        let e = elapsed + board.uploadDelay + boardCorrection
        guard e < total else { return nil }
        let p = position(e)
        let s = segments[p.idx]
        let rem = Double(s.dur) - p.el
        let sec = max(1, Int(ceil(rem)))
        let firstDelay = max(5, Int(((rem - Double(sec - 1)) * 100).rounded()))
        let lastK = max(1, sec - 59)
        gifEnd = lastK > 1 ? (p.idx, lastK - 1) : nil
        var frames: [Frame] = []
        var delays: [Int] = []
        for k in stride(from: sec, through: lastK, by: -1) {
            frames.append(segmentFrame(s, k))
            delays.append(k == sec ? firstDelay : 100)
        }
        if gifEnd == nil {
            if p.idx + 1 < segments.count {
                let nx = segments[p.idx + 1]
                for k in stride(from: nx.dur, through: max(1, nx.dur - 2), by: -1) {
                    frames.append(segmentFrame(nx, k))
                    delays.append(100)
                }
            } else {
                let done = Display(phase: .done, idle: false, paused: false, finished: true, remain: 0, sec: 0,
                                   frac: 0, round: config.rounds, set: config.sets, left: 0)
                frames.append(BoardArt.timer(done, cfg: config, looks: looks))
                delays.append(60000)
            }
        }
        return BoardProtocol.gif(frames, delays: delays)
    }

    private func segmentFrame(_ s: Segment, _ k: Int) -> Frame {
        let d = Display(phase: s.phase, idle: false, paused: false, finished: false, remain: Double(k), sec: k,
                        frac: Double(s.dur - k) / Double(max(1, s.dur)), round: s.round, set: s.set, left: 0)
        return BoardArt.timer(d, cfg: config, looks: looks)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && running
    }

    private func saveRun() {
        Store.save("run", RunState(config: config, t0: t0, pausedE: pausedE, running: running))
    }

    private func restoreRun() {
        let r: RunState? = Store.load("run", nil as RunState?)
        guard let r, r.config == config else { refreshBoard(); return }
        if r.running {
            t0 = r.t0
            running = true
            if elapsed >= total {
                finish(silent: true)
            } else {
                sound.begin()
                lastIdx = position(elapsed).idx
                lastTick = .distantPast
                startTimer()
                updateIdleTimer()
            }
        } else {
            pausedE = r.pausedE
            refreshBoard()
        }
    }

    // MARK: Texts shown in the app

    func color(_ phase: Phase) -> Color { Color(hex: looks[LookKey(phase)].hex) }

    func phaseLabel(_ d: Display) -> String {
        if d.idle { return "KLAAR?" }
        if d.paused { return looks.label(.pause) }
        return looks.label(LookKey(d.phase))
    }

    func bigText(_ d: Display) -> String {
        if d.finished { return "✓" }
        return d.sec >= 60 ? fmt(Double(d.sec)) : "\(d.sec)"
    }

    func subText(_ d: Display) -> String {
        if d.finished { return "Goed gedaan 💪" }
        if d.idle { return "Druk op start" }
        switch d.phase {
        case .work: return "Alles geven!"
        case .rest: return "Even ademen"
        case .prep: return "Maak je klaar"
        case .setrest: return "Herstel"
        case .done: return ""
        }
    }

    // MARK: Schema

    func change(_ key: WritableKeyPath<WorkoutConfig, Int>, by delta: Int, range: ClosedRange<Int>) {
        guard !running else { showToast("Stop eerst de timer"); return }
        var c = config
        c[keyPath: key] = min(range.upperBound, max(range.lowerBound, c[keyPath: key] + delta))
        if c != config { config = c }
    }

    func saveFavorite(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { showToast("Geef je training een naam"); return }
        let fav = Favorite(name: name, config: config, looks: looks)
        if let i = favorites.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            favorites[i] = Favorite(id: favorites[i].id, name: name, config: config, looks: looks)
            showToast("⭐ \(name) bijgewerkt")
        } else {
            favorites.insert(fav, at: 0)
            showToast("⭐ \(name) opgeslagen")
        }
    }

    func apply(_ fav: Favorite) {
        guard !running else { showToast("Stop eerst de timer"); return }
        looks = fav.looks
        config = fav.config
        showToast("\(fav.name) gekozen")
    }

    func delete(_ fav: Favorite) {
        favorites.removeAll { $0.id == fav.id }
        showToast("Training verwijderd")
    }

    func isSelected(_ fav: Favorite) -> Bool { fav.config == config && fav.looks == looks }

    // MARK: Board actions

    func showOnBoard(_ f: Frame) {
        guard !running else { showToast("Stop eerst de timer"); return }
        preview = f
        guard board.isConnected else { showToast("Eerst verbinden met het bord"); return }
        board.show(f)
        showToast("Op het bord")
    }

    func testSound(_ key: WritableKeyPath<SoundSettings, SoundChoice>, _ kind: SoundKind, word: String) {
        sound.play(soundSettings[keyPath: key], kind, word: word)
    }

    func showToast(_ s: String) {
        toast = s
        let id = UUID()
        toastID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toastID == id { self?.toast = nil }
        }
    }
}
