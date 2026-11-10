import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(red: 0.027, green: 0.031, blue: 0.043)
    static let card = Color(red: 0.067, green: 0.075, blue: 0.094)
    static let card2 = Color(red: 0.090, green: 0.102, blue: 0.129)
    static let line = Color(red: 0.133, green: 0.149, blue: 0.184)
    static let muted = Color(red: 0.490, green: 0.518, blue: 0.573)
    static let ok = Color(red: 0.133, green: 0.878, blue: 0.478)
}

extension Color {
    init(hex: String) {
        let c = rgb(hex)
        self.init(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

extension Font {
    /// Bold condensed sport style.
    static func cond(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.4)
            .foregroundColor(Theme.muted)
    }
}

struct PillButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary ? Color.white : Theme.card2)
            .foregroundColor(primary ? .black : .white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(primary ? Color.clear : Theme.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Draws a Frame as glowing LED dots.
struct LEDView: View {
    var frame: Frame
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / CGFloat(Frame.w)
            let r = s * 0.4
            for y in 0..<Frame.h {
                for x in 0..<Frame.w {
                    let c = frame.color(x, y)
                    let on = (c.0 | c.1 | c.2) != 0
                    let col = on ? Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
                                 : Color(white: 0.075)
                    let rect = CGRect(x: CGFloat(x) * s + s / 2 - r, y: CGFloat(y) * s + s / 2 - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(col))
                }
            }
        }
        .aspectRatio(4, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct Header: View {
    @EnvironmentObject var board: Board
    var accent: Color

    var body: some View {
        HStack {
            (Text("ED’S TABATA").font(.cond(24).italic()) + Text(".").font(.cond(24).italic()).foregroundColor(accent))
            Spacer()
            Button { board.connect() } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(board.isConnected ? Theme.ok : Color.gray)
                        .frame(width: 8, height: 8)
                        .shadow(color: board.isConnected ? Theme.ok : .clear, radius: 4)
                    Text(board.isConnected ? "Verbonden" : "LED-bord")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
