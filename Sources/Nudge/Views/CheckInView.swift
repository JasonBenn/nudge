import SwiftUI

struct CheckInView: View {
    let data: CheckInData
    let coordinator: CheckInCoordinator
    let onComplete: (String, String, TabAction) -> Void
    let onDismiss: () -> Void

    @State private var state: CheckInState = .q1
    @State private var triggerResponse = ""
    @State private var replacementResponse = ""
    @State private var customInput = ""
    @State private var revisedReplacementOptions: [String]?
    @State private var isLoadingQ2 = false
    @FocusState private var inputFocused: Bool

    private enum CheckInState {
        case q1
        case q2
        case q3
        case chat(phase: ChatPhase)
        case done
    }

    private enum ChatPhase {
        case trigger
        case replacement
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Nudge")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                // Content
                Group {
                    switch state {
                    case .q1:
                        q1View
                    case .q2:
                        q2View
                    case .q3:
                        q3View
                    case .chat(let phase):
                        chatPhaseView(phase: phase)
                    case .done:
                        doneView
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Q1

    private var q1View: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(data.nudge)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("What pulled you away?")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(data.trigger_options, id: \.self) { option in
                    OptionButton(title: option) {
                        triggerResponse = option
                        coordinator.updateEvent(triggerSelection: option)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state = .q2
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("I'm avoiding feeling...", text: $customInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    )
                    .onSubmit { submitCustomTrigger() }

                Button("Go") {
                    submitCustomTrigger()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Q2

    private var q2Options: [String] {
        revisedReplacementOptions ?? data.replacement_options
    }

    private var q2View: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What would you rather do instead?")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            if isLoadingQ2 {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking about what might help...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            VStack(spacing: 8) {
                ForEach(q2Options, id: \.self) { option in
                    OptionButton(title: option) {
                        replacementResponse = option
                        coordinator.updateEvent(replacementSelection: option)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state = .q3
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("I'd rather read...", text: $customInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    )
                    .onSubmit { submitCustomReplacement() }

                Button("Go") {
                    submitCustomReplacement()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { customInput = "" }
    }

    // MARK: - Q3

    private var q3View: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What about those distracting tabs?")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                OptionButton(title: "Close all distracting tabs now") {
                    completeWithTabAction(.closeAll)
                }
                OptionButton(title: "Close all tabs except the current one") {
                    completeWithTabAction(.closeAllButCurrent)
                }
                OptionButton(title: "Close them in 5 minutes") {
                    completeWithTabAction(.closeInFiveMinutes)
                }
                OptionButton(title: "Leave them open") {
                    completeWithTabAction(.leaveOpen)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Chat

    private func chatPhaseView(phase: ChatPhase) -> some View {
        ChatView(
            messages: coordinator.chatMessages,
            streamingText: coordinator.streamingText,
            onSend: { text in
                coordinator.sendChatMessage(text)
            },
            onDone: {
                Task { @MainActor in
                    let summary = await coordinator.summarizeAndComplete()
                    switch phase {
                    case .trigger:
                        triggerResponse = summary.isEmpty ? triggerResponse : summary
                        // Transition to Q2 immediately, load revised options in background
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state = .q2
                            isLoadingQ2 = true
                        }
                        let revised = await coordinator.generateRevisedQ2(triggerSummary: triggerResponse)
                        isLoadingQ2 = false
                        if let revised {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                revisedReplacementOptions = revised
                            }
                        }
                        coordinator.chatMessages = []
                        coordinator.streamingText = ""
                    case .replacement:
                        replacementResponse = summary.isEmpty ? replacementResponse : summary
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state = .q3
                        }
                    }
                }
            }
        )
        .frame(height: 350)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Good awareness!")
                .font(.system(size: 17, weight: .semibold))

            Text("You've got this.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Button("Close") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func completeWithTabAction(_ action: TabAction) {
        withAnimation(.easeInOut(duration: 0.25)) {
            state = .done
        }
        onComplete(triggerResponse, replacementResponse, action)
    }

    private func submitCustomTrigger() {
        let text = customInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        triggerResponse = text
        coordinator.updateEvent(triggerSelection: text)
        customInput = ""
        coordinator.chatMessages = []
        coordinator.streamingText = ""
        coordinator.sendChatMessage(text)
        withAnimation(.easeInOut(duration: 0.25)) {
            state = .chat(phase: .trigger)
        }
    }

    private func submitCustomReplacement() {
        let text = customInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        replacementResponse = text
        coordinator.updateEvent(replacementSelection: text)
        customInput = ""
        coordinator.chatMessages = []
        coordinator.streamingText = ""
        coordinator.sendChatMessage(text)
        withAnimation(.easeInOut(duration: 0.25)) {
            state = .chat(phase: .replacement)
        }
    }
}

// MARK: - Visual Effect

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
