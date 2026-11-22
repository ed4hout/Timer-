import ActivityKit
import SwiftUI

/// Shared by the app and the widget extension: what the lock screen / Dynamic Island shows.
struct TabataActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var colorHex: String
        var phaseStart: Date
        var phaseEnd: Date
        var countsUp: Bool
        var paused: Bool
        var finished: Bool
        var staticText: String
        var info: String
    }
    var title: String
}

func liveColor(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0xFFFFFF
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// The running clock: iOS counts it itself, so it stays correct even when the app sleeps.
struct LiveClock: View {
    let state: TabataActivityAttributes.ContentState
    var body: some View {
        if state.paused || state.finished {
            Text(state.staticText)
        } else if state.countsUp {
            Text(state.phaseStart, style: .timer)
        } else {
            Text(timerInterval: state.phaseStart...max(state.phaseEnd, state.phaseStart.addingTimeInterval(1)),
                 countsDown: true)
        }
    }
}
