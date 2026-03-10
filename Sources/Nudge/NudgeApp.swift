import SwiftUI
import SwiftData

@main
struct NudgeApp: App {
    let modelContainer: ModelContainer
    @State private var detector = DistractionDetector()
    @State private var coordinator = CheckInCoordinator()

    init() {
        NSApp.setActivationPolicy(.accessory)
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        do {
            let url = URL(fileURLWithPath: Config.dbPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let config = ModelConfiguration(url: url)
            modelContainer = try ModelContainer(
                for: NudgeEvent.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to set up ModelContainer: \(error)")
        }

        coordinator.setup(modelContext: modelContainer.mainContext, detector: detector)
        detector.onDistraction = { [coordinator] url, title in
            coordinator.handleDistraction(url: url, title: title)
        }
        detector.startPolling()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.jasonbenn.nudge.runLatencyTest"),
            object: nil, queue: .main
        ) { [coordinator] _ in coordinator.runLatencyTest() }
        print("[Nudge] Wiring complete — watching for distractions")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                isPaused: detector.isPaused,
                hasActiveCheckIn: coordinator.hasActiveCheckIn,
                onTogglePause: { detector.isPaused.toggle() },
                onShowCheckIn: { coordinator.refocusPanel() },
                onTestNudge: {
                    coordinator.handleDistraction(url: "https://x.com", title: "X / Twitter")
                },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            let icon = coordinator.isLoading
                ? coordinator.animationIcon
                : "eye"
            Image(systemName: icon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(coordinator.isLoading ? Color.purple : Color.primary)
        }
        .menuBarExtraStyle(.menu)
    }
}
