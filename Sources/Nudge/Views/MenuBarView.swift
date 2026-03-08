import SwiftUI

struct MenuBarView: View {
    let isPaused: Bool
    let hasActiveCheckIn: Bool
    let onTogglePause: () -> Void
    let onShowCheckIn: () -> Void
    let onTestNudge: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(isPaused ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(isPaused ? "Paused" : "Watching")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            if hasActiveCheckIn {
                Button("Show Check-in") {
                    onShowCheckIn()
                }
                .buttonStyle(MenuItemButtonStyle())

                Divider()
            }

            Button(isPaused ? "Resume" : "Pause") {
                onTogglePause()
            }
            .buttonStyle(MenuItemButtonStyle())

            Button("Test Nudge") {
                onTestNudge()
            }
            .buttonStyle(MenuItemButtonStyle())

            Divider()

            Button("Quit Nudge") {
                onQuit()
            }
            .buttonStyle(MenuItemButtonStyle())
        }
        .padding(.bottom, 4)
        .frame(width: 200)
    }
}

private struct MenuItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            .onHover { isHovered = $0 }
    }
}
