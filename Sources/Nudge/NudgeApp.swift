import SwiftUI
import SwiftData

@main
struct NudgeApp: App {
    let modelContainer: ModelContainer
    @State private var detector = DistractionDetector()
    @State private var coordinator = CheckInCoordinator()
    @State private var hasSetup = false
    @State private var animationFrame = 0
    @State private var animationTimer: Timer?

    private static let eyeFrames = ["eye", "eye.fill", "eye.circle", "eye.circle.fill", "eye.fill", "eye"]

    init() {
        NSApp.setActivationPolicy(.accessory)

        do {
            let url = URL(fileURLWithPath: Config.dbPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let config = ModelConfiguration(url: url)
            modelContainer = try ModelContainer(
                for: Response.self, NudgeEvent.self, Conversation.self, Message.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to set up ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                isPaused: detector.isPaused,
                onTogglePause: { detector.isPaused.toggle() },
                onTestNudge: {
                    coordinator.handleDistraction(url: "https://x.com", title: "X / Twitter")
                },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .onAppear {
                guard !hasSetup else { return }
                hasSetup = true
                coordinator.setModelContext(modelContainer.mainContext)
                detector.onDistraction = { url, title in
                    coordinator.handleDistraction(url: url, title: title)
                }
                print("[Nudge] Wiring complete — watching for distractions")
            }
        } label: {
            Image(systemName: coordinator.isLoading
                  ? Self.eyeFrames[animationFrame % Self.eyeFrames.count]
                  : "eye")
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: coordinator.isLoading) { _, loading in
            if loading {
                animationFrame = 0
                animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                    Task { @MainActor in
                        animationFrame += 1
                    }
                }
            } else {
                animationTimer?.invalidate()
                animationTimer = nil
            }
        }
    }
}
