import ActivityKit
import SwiftUI
import WidgetKit

@main
struct EdsTabataWidgetBundle: WidgetBundle {
    var body: some Widget {
        TabataLiveActivity()
    }
}

struct TabataLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TabataActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let col = liveColor(s.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(s.label)
                        .font(.system(size: 22, weight: .heavy).width(.condensed))
                        .foregroundColor(col)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveClock(state: s)
                        .font(.system(size: 30, weight: .heavy).width(.condensed))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.info)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
            } compactLeading: {
                Circle().fill(col).frame(width: 10, height: 10)
            } compactTrailing: {
                LiveClock(state: s)
                    .font(.system(size: 15, weight: .bold).width(.condensed))
                    .monospacedDigit()
                    .foregroundColor(col)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 48)
            } minimal: {
                Circle().fill(col).frame(width: 10, height: 10)
            }
            .keylineTint(col)
        }
    }
}

struct LockScreenView: View {
    let state: TabataActivityAttributes.ContentState

    var body: some View {
        let col = liveColor(state.colorHex)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ED’S TABATA")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundColor(.gray)
                Text(state.label)
                    .font(.system(size: 26, weight: .heavy).width(.condensed))
                    .foregroundColor(col)
                    .lineLimit(1)
                Text(state.info)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }
            Spacer()
            LiveClock(state: state)
                .font(.system(size: 48, weight: .heavy).width(.condensed))
                .monospacedDigit()
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
