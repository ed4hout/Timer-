import Foundation

// MARK: - Workout

enum Phase: String, Codable, CaseIterable {
    case prep, work, rest, setrest, done
}

struct WorkoutConfig: Codable, Equatable {
    var prep = 10
    var work = 20
    var rest = 10
    var rounds = 8
    var sets = 1
    var setrest = 60
}

struct Segment: Equatable {
    let phase: Phase
    let dur: Int
    let round: Int
    let set: Int
}

func buildSegments(_ c: WorkoutConfig) -> [Segment] {
    var s: [Segment] = []
    if c.prep > 0 { s.append(Segment(phase: .prep, dur: c.prep, round: 0, set: 1)) }
    for st in 1...max(1, c.sets) {
        for r in 1...max(1, c.rounds) {
            s.append(Segment(phase: .work, dur: c.work, round: r, set: st))
            if c.rest > 0 && r < c.rounds {
                s.append(Segment(phase: .rest, dur: c.rest, round: r, set: st))
            }
        }
        if st < c.sets && c.setrest > 0 {
            s.append(Segment(phase: .setrest, dur: c.setrest, round: c.rounds, set: st))
        }
    }
    return s
}

/// "m:ss"
func fmt(_ seconds: Double) -> String {
    let v = max(0, Int(ceil(seconds - 1e-6)))
    return "\(v / 60):" + String(format: "%02d", v % 60)
}

// MARK: - Texts & colours per phase

enum LookKey: String, Codable, CaseIterable, Identifiable {
    case prep, work, rest, setrest, done, pause
    var id: String { rawValue }
    var title: String {
        switch self {
        case .prep: return "Voorbereiden"
        case .work: return "Werk"
        case .rest: return "Rust"
        case .setrest: return "Setpauze"
        case .done: return "Einde"
        case .pause: return "Pauze"
        }
    }
    init(_ phase: Phase) { self = LookKey(rawValue: phase.rawValue) ?? .work }
}

struct PhaseLook: Codable, Equatable {
    var text: String
    var hex: String
}

struct Looks: Codable, Equatable {
    static let defaults: [LookKey: PhaseLook] = [
        .prep: PhaseLook(text: "START", hex: "#FFCC00"),
        .work: PhaseLook(text: "WERK", hex: "#FF2A1F"),
        .rest: PhaseLook(text: "RUST", hex: "#18E070"),
        .setrest: PhaseLook(text: "PAUZE", hex: "#2EA8FF"),
        .done: PhaseLook(text: "TOP!", hex: "#C6FF00"),
        .pause: PhaseLook(text: "PAUZE", hex: "#FFFFFF"),
    ]

    var items: [String: PhaseLook]

    init() {
        var d: [String: PhaseLook] = [:]
        for k in LookKey.allCases { d[k.rawValue] = Looks.defaults[k] }
        items = d
    }

    subscript(_ k: LookKey) -> PhaseLook {
        get { items[k.rawValue] ?? Looks.defaults[k]! }
        set { items[k.rawValue] = newValue }
    }

    /// Text shown for a phase; falls back to the default when left empty.
    func label(_ k: LookKey) -> String {
        let t = self[k].text
        return t.isEmpty ? (Looks.defaults[k]?.text ?? "") : t
    }
}

struct Favorite: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var config: WorkoutConfig
    var looks: Looks
}

// MARK: - Sound

enum SoundChoice: String, Codable, CaseIterable, Identifiable {
    case off, beep, high, double, click, bell, boxing, whistle, gong, horn, voice
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Geen geluid"
        case .beep: return "Piep"
        case .high: return "Hoge piep"
        case .double: return "Dubbele piep"
        case .click: return "Klik"
        case .bell: return "Bel"
        case .boxing: return "Boksbel"
        case .whistle: return "Fluitje"
        case .gong: return "Gong"
        case .horn: return "Hoorn"
        case .voice: return "Stem"
        }
    }
}

enum SoundKind { case count, phase, done }

struct SoundSettings: Codable, Equatable {
    var volume: Double = 0.9
    var count: SoundChoice = .beep
    var work: SoundChoice = .boxing
    var rest: SoundChoice = .bell
    var done: SoundChoice = .gong
    /// Lower other music (Spotify) while a workout runs.
    var duck: Bool = false
}

// MARK: - Persistence

enum Store {
    static func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode(T.self, from: d) else { return fallback }
        return v
    }
    static func save<T: Encodable>(_ key: String, _ value: T) {
        if let d = try? JSONEncoder().encode(value) { UserDefaults.standard.set(d, forKey: key) }
    }
    static func remove(_ key: String) { UserDefaults.standard.removeObject(forKey: key) }
}

struct RunState: Codable {
    var config: WorkoutConfig
    var t0: Date
    var pausedE: Double
    var running: Bool
}
