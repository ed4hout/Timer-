import Foundation

typealias RGB3 = (UInt8, UInt8, UInt8)

func rgb(_ hex: String) -> RGB3 {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0xFFFFFF
    return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}

func dim(_ c: RGB3, _ f: Double) -> RGB3 {
    (UInt8(Double(c.0) * f), UInt8(Double(c.1) * f), UInt8(Double(c.2) * f))
}

/// One 64×16 picture for the LED board (RGBA).
struct Frame: Equatable {
    static let w = 64
    static let h = 16
    var px: [UInt8]

    init() {
        px = [UInt8](repeating: 0, count: Frame.w * Frame.h * 4)
        for i in stride(from: 3, to: px.count, by: 4) { px[i] = 255 }
    }

    mutating func set(_ x: Int, _ y: Int, _ c: RGB3) {
        guard x >= 0, y >= 0, x < Frame.w, y < Frame.h else { return }
        let i = (y * Frame.w + x) * 4
        px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2
    }

    func color(_ x: Int, _ y: Int) -> RGB3 {
        let i = (y * Frame.w + x) * 4
        return (px[i], px[i + 1], px[i + 2])
    }
}

// MARK: - 3×5 pixel font

enum PixelFont {
    static let glyphs: [Character: [UInt8]] = [
        "0": [7,5,5,5,7], "1": [2,6,2,2,7], "2": [7,1,7,4,7], "3": [7,1,7,1,7], "4": [5,5,7,1,1],
        "5": [7,4,7,1,7], "6": [7,4,7,5,7], "7": [7,1,1,2,2], "8": [7,5,7,5,7], "9": [7,5,7,1,7],
        "A": [2,5,7,5,5], "B": [6,5,6,5,6], "C": [3,4,4,4,3], "D": [6,5,5,5,6], "E": [7,4,6,4,7],
        "F": [7,4,6,4,4], "G": [3,4,5,5,3], "H": [5,5,7,5,5], "I": [7,2,2,2,7], "J": [1,1,1,5,2],
        "K": [5,5,6,5,5], "L": [4,4,4,4,7], "M": [5,7,7,5,5], "N": [6,5,5,5,5], "O": [2,5,5,5,2],
        "P": [6,5,6,4,4], "Q": [2,5,5,6,3], "R": [6,5,6,5,5], "S": [3,4,2,1,6], "T": [7,2,2,2,2],
        "U": [5,5,5,5,7], "V": [5,5,5,5,2], "W": [5,5,5,7,5], "X": [5,5,2,5,5], "Y": [5,5,2,2,2],
        "Z": [7,1,2,4,7], " ": [0,0,0,0,0], "/": [1,1,2,4,4], ":": [0,2,0,2,0], "!": [2,2,2,0,2],
        "-": [0,0,7,0,0], ".": [0,0,0,0,2], "?": [6,1,2,0,2], "+": [0,2,7,2,0], "'": [2,2,0,0,0],
        "♥": [5,7,7,7,2],
    ]

    static func width(_ s: String, _ scale: Int) -> Int {
        s.isEmpty ? 0 : s.count * 4 * scale - scale
    }

    static func draw(_ f: inout Frame, _ s: String, x: Int, y: Int, scale sc: Int, color c: RGB3) {
        var cx = x
        for ch in s.uppercased() {
            let g = glyphs[ch] ?? glyphs["?"]!
            for r in 0..<5 {
                for k in 0..<3 where (Int(g[r]) & (4 >> k)) != 0 {
                    for a in 0..<sc {
                        for d in 0..<sc { f.set(cx + k * sc + d, y + r * sc + a, c) }
                    }
                }
            }
            cx += 4 * sc
        }
    }

    /// Upper-case, strip accents, keep only characters the board can show.
    static func sanitize(_ s: String, max: Int = 8) -> String {
        let folded = s.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "nl_NL")).uppercased()
        return String(folded.filter { glyphs[$0] != nil }.prefix(max))
    }
}

// MARK: - What the timer looks like on the board

struct Display {
    var phase: Phase
    var idle: Bool
    var paused: Bool
    var finished: Bool
    var remain: Double
    var sec: Int
    var frac: Double
    var round: Int
    var set: Int
    var left: Double
}

enum BoardArt {
    static func timer(_ d: Display, cfg: WorkoutConfig, looks: Looks) -> Frame {
        var f = Frame()
        if d.idle {
            let t = "TABATA"
            PixelFont.draw(&f, t, x: (Frame.w - PixelFont.width(t, 2)) / 2, y: 3, scale: 2, color: rgb(looks[.done].hex))
            return f
        }
        if d.finished {
            let t = looks.label(.done)
            let sc = PixelFont.width(t, 3) <= Frame.w ? 3 : (PixelFont.width(t, 2) <= Frame.w ? 2 : 1)
            PixelFont.draw(&f, t, x: (Frame.w - PixelFont.width(t, sc)) / 2, y: sc == 3 ? 0 : (sc == 2 ? 3 : 5), scale: sc, color: rgb(looks[.done].hex))
            return f
        }
        let col = rgb(looks[LookKey(d.phase)].hex)
        var num = "\(d.sec)"
        var sc = 3
        var y = 0
        if d.sec > 99 || PixelFont.width(num, 3) > 27 {
            num = fmt(Double(d.sec)); sc = 2; y = 3
        }
        let nw = PixelFont.width(num, sc)
        PixelFont.draw(&f, num, x: Frame.w - nw, y: y, scale: sc, color: d.paused ? dim(col, 0.45) : col)
        let leftW = Frame.w - nw - 2
        let maxChars = max(1, (leftW + 1) / 4)
        let label = d.paused ? looks.label(.pause) : looks.label(LookKey(d.phase))
        PixelFont.draw(&f, String(label.prefix(maxChars)), x: 0, y: 0, scale: 1, color: d.paused ? rgb(looks[.pause].hex) : col)
        let rd = d.phase == .prep ? 0 : d.round
        var info = "\(rd)/\(cfg.rounds)"
        if cfg.sets > 1 && PixelFont.width(info + " S\(d.set)", 1) <= leftW { info += " S\(d.set)" }
        PixelFont.draw(&f, info, x: 0, y: 7, scale: 1, color: (200, 200, 200))
        let bw = max(0, leftW - 1)
        let fill = Int((Double(bw) * d.frac).rounded())
        for x in 0..<bw {
            for yy in 14..<16 { f.set(x, yy, x < fill ? col : dim(col, 0.05)) }
        }
        return f
    }

    static func message(_ s: String) -> Frame {
        var f = Frame()
        let t = PixelFont.sanitize(s, max: 16)
        let sc = PixelFont.width(t, 2) <= Frame.w ? 2 : 1
        PixelFont.draw(&f, t, x: (Frame.w - PixelFont.width(t, sc)) / 2, y: sc == 2 ? 3 : 5, scale: sc, color: rgb("#C6FF00"))
        return f
    }

    static func icon(_ ic: SportIcon) -> Frame {
        var f = Frame()
        let rows = ic.art
        let y0 = (Frame.h - rows.count) / 2
        var minX = 99, maxX = -1
        for r in rows { for (x, ch) in r.enumerated() where ch != "." { minX = min(minX, x); maxX = max(maxX, x) } }
        let iw = maxX - minX + 1
        let ox = 1
        for (y, r) in rows.enumerated() {
            for (x, ch) in r.enumerated() where ch != "." {
                f.set(ox + x - minX, y0 + y, rgb(SportIcon.palette[ch] ?? "#FFFFFF"))
            }
        }
        let t = ic.word
        let area = Frame.w - (ox + iw + 2)
        let sc = PixelFont.width(t, 2) <= area ? 2 : 1
        let tx = ox + iw + 2 + (area - PixelFont.width(t, sc)) / 2
        PixelFont.draw(&f, t, x: tx, y: sc == 2 ? 3 : 5, scale: sc, color: rgb(SportIcon.palette[ic.color] ?? "#FFFFFF"))
        return f
    }
}

// MARK: - Sport pictures

struct SportIcon: Identifiable {
    var id: String { word }
    let word: String
    let color: Character
    let art: [String]

    static let palette: [Character: String] = [
        "w": "#FFFFFF", "g": "#A7ADB6", "k": "#5D636C", "r": "#FF2A1F", "o": "#FF7A00",
        "y": "#FFD000", "b": "#2EA8FF", "G": "#22E07A", "p": "#FF4FA3",
    ]

    static let all: [SportIcon] = [
        SportIcon(word: "LIFT!", color: "w", art: ["..gg........gg..", ".gggg......gggg.", ".gggg......gggg.", ".ggggg....ggggg.", ".ggggwwwwwwgggg.", ".ggggwwwwwwgggg.", ".ggggg....ggggg.", ".gggg......gggg.", ".gggg......gggg.", "..gg........gg.."]),
        SportIcon(word: "BURN!", color: "o", art: ["......o.........", ".....oo.........", ".....ooo........", "....oooo..o.....", "....ooooo.oo....", "...oooooooooo...", "...ooooyooooo...", "..oooooyyoooo...", "..ooooyyyyooo...", "..oooyyyyyyoo...", "..ooyyywwyyoo...", "...oyywwwwyo....", "....yywwwyy.....", ".....yyyyy......"]),
        SportIcon(word: "POWER", color: "y", art: [".........yyy....", "........yyy.....", ".......yyy......", "......yyy.......", ".....yyy........", "....yyyyyyy.....", "....yyyyyyy.....", ".......yyy......", "......yyy.......", ".....yyy........", "....yyy.........", "...yy...........", "..y............."]),
        SportIcon(word: "CARDIO", color: "r", art: ["...rrr...rrr....", "..rrrrr.rrrrr...", ".rrwrrrrrrrrrr..", ".rwrrrrrrrrrrr..", ".rrrrrrrrrrrrr..", "..rrrrrrrrrrr...", "...rrrrrrrrr....", "....rrrrrrr.....", ".....rrrrr......", "......rrr.......", ".......r........"]),
        SportIcon(word: "TIJD!", color: "w", art: ["......ww........", ".....wwww.......", "......ww..w.....", "....wwwwww.w....", "...w......w.....", "..w...r....w....", "..w...r....w....", ".w....r.....w...", ".w....rrr...w...", ".w..........w...", "..w........w....", "..w........w....", "...w......w.....", "....wwwwww......"]),
        SportIcon(word: "WINNER", color: "y", art: ["..yyyyyyyyyy....", "yyyyyyyyyyyyyy..", "y.yyyyyyyyyy.y..", "y.yyyywyyyyy.y..", ".yyyyywyyyyyy...", "...yyyyyyyy.....", "....yyyyyy......", ".....yyyy.......", "......yy........", "......yy........", ".....yyyy.......", "....yyyyyy......", "....oooooo......"]),
        SportIcon(word: "RUN!", color: "G", art: ["..........ww....", "..........ww....", "......wwww......", ".....w..ww.w....", "........ww..w...", ".......www......", "......w...w.....", ".....w.....w....", "....w.......ww..", "..ww............"]),
        SportIcon(word: "SWING", color: "g", art: [".....kkkkk......", "....k.....k.....", "....k.....k.....", "...kkkkkkkkk....", "..kgggggggggk...", ".kgggwgggggggk..", ".kggwggggggggk..", ".kgggggggggggk..", ".kgggggggggggk..", "..kgggggggggk...", "...kkkkkkkkk...."]),
        SportIcon(word: "DRINK", color: "b", art: [".......b........", "......bbb.......", ".....bbbbb......", "....bbbbbbb.....", "...bbbbbbbbb....", "...bwbbbbbbb....", "..bwbbbbbbbbb...", "..bwbbbbbbbbb...", "..bbbbbbbbbbb...", "...bbbbbbbbb....", "....bbbbbbb.....", ".....bbbbb......"]),
        SportIcon(word: "TOP!", color: "G", art: ["..............GG", ".............GG.", "............GG..", "...........GG...", "..........GG....", "GG.......GG.....", ".GG.....GG......", "..GG...GG.......", "...GG.GG........", "....GGG.........", ".....G.........."]),
    ]
}
