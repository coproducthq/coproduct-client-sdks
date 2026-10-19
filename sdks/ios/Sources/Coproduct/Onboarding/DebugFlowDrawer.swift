#if DEBUG
import SwiftUI

/// `DEBUG`-only overlay offering "Restart flow" (clears persisted progress,
/// rebuilds from `startScreenId`) and "Refresh" (polls immediately, then
/// re-fetches), so a content edit is visibly guaranteed on refresh rather
/// than only eventually. No cross-platform pixel-parity requirement --
/// RN/Flutter's own drawers are each platform's own look.
struct DebugFlowDrawer: View {
    let onRestartFlow: () -> Void
    let onRefresh: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                Button("Restart flow", action: onRestartFlow)
                Button("Refresh", action: onRefresh)
            }
            Button(isExpanded ? "Close" : "Debug") { isExpanded.toggle() }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding()
    }
}
#endif
