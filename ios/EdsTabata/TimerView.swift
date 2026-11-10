import SwiftUI

struct TimerView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var board: Board

    var body: some View {
        let d = model.display
        let col = model.color(d.phase)
        GeometryReader { geo in
            let ring = min(geo.size.width * 0.80, geo.size.height * 0.46)
            ZStack {
                Theme.bg.ignoresSafeArea()
                RadialGradient(colors: [col.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.3),
                               startRadius: 0, endRadius: geo.size.width * 0.9)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: d.phase)

                VStack(spacing: 0) {
                    Header(accent: col)
                    Spacer(minLength: 6)

                    ZStack {
                        Circle().stroke(Color.white.opacity(0.07), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: max(0.0001, 1 - d.frac))
                            .stroke(col, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: col.opacity(0.6), radius: 10)
                        VStack(spacing: 0) {
                            Text(model.phaseLabel(d))
                                .font(.cond(26))
                                .kerning(3)
                                .foregroundColor(col)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(model.bigText(d))
                                .font(.cond(ring * 0.40))
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                            Text(model.subText(d))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.muted)
                        }
                        .padding(30)
                    }
                    .frame(width: ring, height: ring)

                    RoundBars(rounds: model.config.rounds, current: d.phase == .prep ? 0 : d.round,
                              phase: d.phase, finished: d.finished, color: col)
                        .padding(.top, 12)

                    HStack {
                        Meta(value: "\(d.phase == .prep ? 0 : d.round)/\(model.config.rounds)", label: "Ronde")
                        Meta(value: "\(d.set)/\(model.config.sets)", label: "Set")
                        Meta(value: fmt(d.left), label: "Resterend")
                    }
                    .padding(.top, 8)

                    HStack(spacing: 28) {
                        RoundIcon(system: "arrow.counterclockwise") { model.reset() }
                        Button { model.toggle() } label: {
                            Image(systemName: model.running ? "pause.fill" : "play.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 78, height: 78)
                                .background(col)
                                .clipShape(Circle())
                                .shadow(color: col.opacity(0.45), radius: 18, y: 8)
                        }
                        .buttonStyle(.plain)
                        RoundIcon(system: "forward.end.fill") { model.skip() }
                    }
                    .padding(.top, 12)

                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionLabel(text: "Op het LED-bord")
                            Spacer()
                            SectionLabel(text: board.isConnected ? "live" : "niet verbonden")
                        }
                        LEDView(frame: model.preview)
                    }
                    .padding(10)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct RoundBars: View {
    let rounds: Int
    let current: Int
    let phase: Phase
    let finished: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, rounds), id: \.self) { n in
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill(n))
                    .frame(maxWidth: 26)
                    .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func fill(_ n: Int) -> Color {
        if finished || n < current || (n == current && phase != .work) { return color }
        if n == current { return color.opacity(0.45) }
        return Color.white.opacity(0.08)
    }
}

private struct Meta: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.cond(22, .bold)).monospacedDigit()
            Text(label.uppercased()).font(.system(size: 10, weight: .medium)).kerning(1.2).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RoundIcon: View {
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(Theme.card)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
