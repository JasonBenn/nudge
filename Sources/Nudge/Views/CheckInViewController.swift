import AppKit

// MARK: - CheckInViewController

final class CheckInViewController: NSViewController {
    private enum State: Equatable {
        case q1, q2, q3, done
        case chat(_ phase: ChatPhase)
    }
    private enum ChatPhase: Equatable { case trigger, replacement }
    private let data: CheckInData
    private unowned let coordinator: CheckInCoordinator
    private let onComplete: (String, String, TabAction) -> Void
    private let onDismiss: () -> Void

    private var triggerResponse = ""
    private var replacementResponse = ""
    private var revisedReplacementOptions: [String]?
    private var isLoadingQ2 = false

    private var currentState: State = .q1
    private weak var panel: FloatingPanel?
    private let contentContainer = NSView()
    private var currentChild: NSView?
    private weak var chatViewRef: AppKitChatView?
    private weak var q2ViewRef: Q2View?
    private weak var backButton: NSButton?
    private var timerLabel: NSTextField!
    private var elapsedTimer: Timer?
    private var startTime: Date?

    init(data: CheckInData, coordinator: CheckInCoordinator,
         onComplete: @escaping (String, String, TabAction) -> Void,
         onDismiss: @escaping () -> Void) {
        self.data = data
        self.coordinator = coordinator
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true

        let header = makeHeader()
        let sep = makeSep()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(sep)
        root.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 420),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            sep.topAnchor.constraint(equalTo: header.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: sep.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        panel = view.window as? FloatingPanel
        startTime = Date()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let mins = elapsed / 60
            let secs = elapsed % 60
            self.timerLabel.stringValue = String(format: "%d:%02d", mins, secs)
        }
        transition(to: .q1)
    }

    deinit {
        elapsedTimer?.invalidate()
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let timer = NSTextField(labelWithString: "0:00")
        timer.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timer.textColor = .tertiaryLabelColor
        timer.translatesAutoresizingMaskIntoConstraints = false
        self.timerLabel = timer

        let backBtn = NSButton()
        backBtn.bezelStyle = .inline
        backBtn.isBordered = false
        backBtn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backBtn.contentTintColor = .secondaryLabelColor
        backBtn.target = self
        backBtn.action = #selector(goBack)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.isHidden = true
        self.backButton = backBtn

        let label = NSTextField(labelWithString: "Nudge")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = NSButton()
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(closePanel)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(timer)
        header.addSubview(backBtn)
        header.addSubview(label)
        header.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            timer.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            timer.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backBtn.leadingAnchor.constraint(equalTo: timer.trailingAnchor, constant: 4),
            backBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 20),
            backBtn.heightAnchor.constraint(equalToConstant: 20),
            label.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            closeBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),
            closeBtn.heightAnchor.constraint(equalToConstant: 20),
        ])
        return header
    }

    @objc private func closePanel() { onDismiss() }

    @objc private func goBack() {
        switch currentState {
        case .q2:
            transition(to: .q1)
        case .q3:
            transition(to: .q2)
        case .chat(let phase):
            coordinator.chatMessages = []
            coordinator.streamingText = ""
            switch phase {
            case .trigger: transition(to: .q1)
            case .replacement: transition(to: .q2)
            }
        default:
            break
        }
    }

    // MARK: - State Transitions

    private func transition(to state: State) {
        currentState = state
        currentChild?.removeFromSuperview()
        backButton?.isHidden = (state == .q1 || state == .done)

        let child: NSView
        switch state {
        case .q1:
            child = Q1View(
                nudge: data.nudge,
                options: data.trigger_options,
                onSelect: { [weak self] opt in
                    self?.triggerResponse = opt
                    self?.coordinator.updateEvent(triggerSelection: opt)
                    self?.transition(to: .q2)
                },
                onDiscuss: { [weak self] text in self?.submitCustomTrigger(text) },
                onShortCircuit: { [weak self] reason in
                    self?.triggerResponse = reason
                    self?.coordinator.updateEvent(triggerSelection: reason)
                    self?.completeWithTabAction(.closeAll)
                }
            )
        case .q2:
            let v = Q2View(
                options: revisedReplacementOptions ?? data.replacement_options,
                isLoading: isLoadingQ2,
                onSelect: { [weak self] opt in
                    self?.replacementResponse = opt
                    self?.coordinator.updateEvent(replacementSelection: opt)
                    self?.transition(to: .q3)
                },
                onCustomSubmit: { [weak self] text in self?.submitCustomReplacement(text) }
            )
            q2ViewRef = v
            child = v
        case .q3:
            child = Q3View(onSelect: { [weak self] action in self?.completeWithTabAction(action) })
        case .chat(let phase):
            let v = AppKitChatView(
                onSend: { [weak self] text in self?.coordinator.sendChatMessage(text) },
                onDone: { [weak self] in self?.handleChatDone(phase: phase) }
            )
            chatViewRef = v
            v.update(messages: coordinator.chatMessages, streamingText: coordinator.streamingText)
            child = v
        case .done:
            child = DoneView(onClose: { [weak self] in self?.onDismiss() })
        }

        child.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            child.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])
        currentChild = child
        resizePanel(for: child)
    }

    private func resizePanel(for child: NSView, animate: Bool = true) {
        child.layoutSubtreeIfNeeded()
        let maxH = maxPanelHeight()
        let totalH = min(44 + 1 + child.fittingSize.height, maxH)
        guard let p = panel else { return }
        let r = p.frame
        let newH = max(totalH, 200)
        // Keep top edge fixed by adjusting origin.y
        let newY = r.origin.y + r.height - newH
        p.setFrame(NSRect(x: r.origin.x, y: newY, width: 420, height: newH),
                   display: true, animate: animate)
    }

    private func maxPanelHeight() -> CGFloat {
        guard let screen = panel?.screen ?? NSScreen.main else { return 700 }
        return screen.visibleFrame.height - 40
    }

    // MARK: - Actions

    private func submitCustomTrigger(_ text: String) {
        triggerResponse = text
        coordinator.updateEvent(triggerSelection: text)
        coordinator.chatMessages = []
        coordinator.streamingText = ""
        coordinator.sendChatMessage(text)
        transition(to: .chat(.trigger))
    }

    private func submitCustomReplacement(_ text: String) {
        replacementResponse = text
        coordinator.updateEvent(replacementSelection: text)
        coordinator.chatMessages = []
        coordinator.streamingText = ""
        coordinator.sendChatMessage(text)
        transition(to: .chat(.replacement))
    }

    private func completeWithTabAction(_ action: TabAction) {
        transition(to: .done)
        onComplete(triggerResponse, replacementResponse, action)
    }

    private func handleChatDone(phase: ChatPhase) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let summary = await self.coordinator.summarizeAndComplete()
            switch phase {
            case .trigger:
                // Use summary for Q2 generation but keep triggerResponse as user's original text
                let triggerSummary = summary.isEmpty ? self.triggerResponse : summary
                self.isLoadingQ2 = true
                self.transition(to: .q2)
                let revised = await self.coordinator.generateRevisedQ2(triggerSummary: triggerSummary)
                self.isLoadingQ2 = false
                if let revised {
                    self.revisedReplacementOptions = revised
                    self.q2ViewRef?.setOptions(revised)
                }
                self.q2ViewRef?.setLoading(false)
                self.coordinator.chatMessages = []
                self.coordinator.streamingText = ""
            case .replacement:
                // Don't overwrite user's replacement choice with AI summary
                self.transition(to: .q3)
            }
        }
    }

    // MARK: - Public

    func chatStateChanged(messages: [ChatMessage], streamingText: String) {
        chatViewRef?.update(messages: messages, streamingText: streamingText)
    }

    func resizePanelToFitChat() {
        guard let child = currentChild else { return }
        resizePanel(for: child, animate: false)
    }
}

// MARK: - OptionNSButton

private final class OptionNSButton: NSView {
    private let action: () -> Void
    private let label: NSTextField
    private var isHovered = false

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        self.label = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        refreshColors()

        label.font = .systemFont(ofSize: 14)
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 340
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refreshColors() {
        let bg = isHovered
            ? NSColor.selectedControlColor.withAlphaComponent(0.3)
            : NSColor.controlBackgroundColor
        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  refreshColors() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; refreshColors() }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Q1View

private final class Q1View: NSView {
    private let onSelect: (String) -> Void
    private let onDiscuss: (String) -> Void
    private let onShortCircuit: (String) -> Void
    private var textInput: GrowingTextInput!
    private var submitTarget: ActionTarget!
    private var discussTarget: ActionTarget!
    private var shortCircuitTarget: ActionTarget!

    init(nudge: String, options: [String],
         onSelect: @escaping (String) -> Void,
         onDiscuss: @escaping (String) -> Void,
         onShortCircuit: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self.onDiscuss = onDiscuss
        self.onShortCircuit = onShortCircuit
        super.init(frame: .zero)

        let stack = vstack(spacing: 16)
        let views: [NSView] = [
            bodyLabel(nudge),
            secondaryLabel("What pulled you away?"),
            optionButtons(options, onSelect: onSelect),
            customInputSection(placeholder: "Something else..."),
        ]
        for v in views {
            stack.addArrangedSubview(v)
            fillWidth(v, in: stack)
        }

        addSubview(stack)
        pin(stack, insets: 20)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func trimmedText() -> String {
        textInput.text.trimmingCharacters(in: .whitespaces)
    }

    private func customInputSection(placeholder: String) -> NSView {
        textInput = GrowingTextInput(placeholder: placeholder, onSubmit: { [weak self] text in
            self?.onSelect(text)
        })

        submitTarget = ActionTarget { [weak self] in
            guard let self else { return }
            let text = self.trimmedText()
            guard !text.isEmpty else { return }
            self.onSelect(text)
        }
        discussTarget = ActionTarget { [weak self] in
            guard let self else { return }
            let text = self.trimmedText()
            guard !text.isEmpty else { return }
            self.onDiscuss(text)
        }
        shortCircuitTarget = ActionTarget { [weak self] in
            guard let self else { return }
            let text = self.trimmedText()
            self.onShortCircuit(text.isEmpty ? "(closed without reason)" : text)
        }

        let submitBtn = NSButton(title: "Submit", target: submitTarget, action: #selector(ActionTarget.fire))
        submitBtn.bezelStyle = .rounded
        submitBtn.translatesAutoresizingMaskIntoConstraints = false

        let discussBtn = NSButton(title: "Discuss", target: discussTarget, action: #selector(ActionTarget.fire))
        discussBtn.bezelStyle = .rounded
        discussBtn.translatesAutoresizingMaskIntoConstraints = false

        let shortCircuitBtn = NSButton(title: "Close all", target: shortCircuitTarget, action: #selector(ActionTarget.fire))
        shortCircuitBtn.bezelStyle = .rounded
        shortCircuitBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnRow = hstack(spacing: 8)
        btnRow.addArrangedSubview(submitBtn)
        btnRow.addArrangedSubview(discussBtn)
        btnRow.addArrangedSubview(shortCircuitBtn)

        let wrapper = vstack(spacing: 8)
        wrapper.addArrangedSubview(textInput)
        wrapper.addArrangedSubview(btnRow)
        fillWidth(textInput, in: wrapper)
        return wrapper
    }
}

// MARK: - Q2View

private final class Q2View: NSView {
    private let onCustomSubmit: (String) -> Void
    private var onSelect: (String) -> Void
    private var textInput: GrowingTextInput!
    private var goTarget: ActionTarget!
    private var optStack: NSStackView!
    private let loadingView: NSStackView
    private let spinner = NSProgressIndicator()

    init(options: [String], isLoading: Bool,
         onSelect: @escaping (String) -> Void,
         onCustomSubmit: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self.onCustomSubmit = onCustomSubmit
        self.loadingView = vstack(spacing: 8)
        super.init(frame: .zero)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        loadingView.alignment = .centerX
        loadingView.addArrangedSubview(spinner)
        loadingView.addArrangedSubview(secondaryLabel("Thinking about what might help..."))
        loadingView.isHidden = !isLoading
        if isLoading { spinner.startAnimation(nil) }

        optStack = optionButtons(options, onSelect: onSelect)

        let stack = vstack(spacing: 16)
        let views: [NSView] = [
            bodyLabel("What would you rather do instead?"),
            loadingView,
            optStack,
            customRow(placeholder: "I'd rather..."),
        ]
        for v in views {
            stack.addArrangedSubview(v)
            fillWidth(v, in: stack)
        }

        addSubview(stack)
        pin(stack, insets: 20)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setOptions(_ newOptions: [String]) {
        for v in optStack.arrangedSubviews { optStack.removeArrangedSubview(v); v.removeFromSuperview() }
        for opt in newOptions {
            let btn = OptionNSButton(title: opt) { [weak self] in self?.onSelect(opt) }
            optStack.addArrangedSubview(btn)
            fillWidth(btn, in: optStack)
        }
    }

    func setLoading(_ loading: Bool) {
        loadingView.isHidden = !loading
        loading ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    private func customRow(placeholder: String) -> NSView {
        textInput = GrowingTextInput(placeholder: placeholder, onSubmit: { [weak self] text in
            self?.onCustomSubmit(text)
        })

        goTarget = ActionTarget { [weak self] in
            guard let self, !self.textInput.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            self.onCustomSubmit(self.textInput.text.trimmingCharacters(in: .whitespaces))
        }
        let goBtn = NSButton(title: "Go", target: goTarget, action: #selector(ActionTarget.fire))
        goBtn.bezelStyle = .rounded
        goBtn.translatesAutoresizingMaskIntoConstraints = false

        let row = hstack(spacing: 8)
        row.addArrangedSubview(textInput)
        row.addArrangedSubview(goBtn)
        textInput.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }
}

// MARK: - Q3View

private final class Q3View: NSView {
    init(onSelect: @escaping (TabAction) -> Void) {
        super.init(frame: .zero)

        let choices: [(String, TabAction)] = [
            ("Close all distracting tabs now", .closeAll),
            ("Close all tabs except the current one", .closeAllButCurrent),
            ("Close them in 5 minutes", .closeInFiveMinutes),
            ("Leave them open", .leaveOpen),
        ]

        let opts = vstack(spacing: 8)
        for (title, action) in choices {
            let btn = OptionNSButton(title: title) { onSelect(action) }
            opts.addArrangedSubview(btn)
            fillWidth(btn, in: opts)
        }

        let stack = vstack(spacing: 16)
        let views: [NSView] = [bodyLabel("What about those distracting tabs?"), opts]
        for v in views {
            stack.addArrangedSubview(v)
            fillWidth(v, in: stack)
        }

        addSubview(stack)
        pin(stack, insets: 20)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - AppKitChatView

private final class AppKitChatView: NSView, NSTextFieldDelegate {
    private let onSend: (String) -> Void
    private let onDone: () -> Void

    private let scrollView = NSScrollView()
    private let bubbleStack: NSStackView
    private let inputField = NSTextField()

    private var displayedCount = 0
    private var streamingLabel: NSTextField?
    private var streamingRow: NSView?
    private var scrollHeightConstraint: NSLayoutConstraint!

    init(onSend: @escaping (String) -> Void, onDone: @escaping () -> Void) {
        self.onSend = onSend
        self.onDone = onDone
        self.bubbleStack = vstack(spacing: 10)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Scroll view + bubble stack
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStack.alignment = .width
        docView.addSubview(bubbleStack)
        NSLayoutConstraint.activate([
            bubbleStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: 12),
            bubbleStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: 16),
            bubbleStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -16),
            bubbleStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -12),
        ])
        scrollView.documentView = docView

        // Input area
        inputField.placeholderString = "Reply..."
        inputField.bezelStyle = .roundedBezel
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false

        let sendBtn = NSButton(title: "Send", target: self, action: #selector(sendMessage))
        sendBtn.bezelStyle = .inline
        sendBtn.isBordered = false
        sendBtn.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = hstack(spacing: 10)
        inputRow.addArrangedSubview(inputField)
        inputRow.addArrangedSubview(sendBtn)
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Done button
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneBtn.bezelStyle = .inline
        doneBtn.isBordered = false
        doneBtn.translatesAutoresizingMaskIntoConstraints = false

        let sep1 = makeSep()
        let sep2 = makeSep()

        [scrollView, sep1, inputRow, sep2, doneBtn].forEach { addSubview($0) }

        // Use a height constraint on the scroll view that tracks content
        scrollHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 60)
        scrollHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollHeightConstraint,
            docView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            sep1.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            sep1.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep1.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 8),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            inputField.heightAnchor.constraint(equalToConstant: 34),
            sep2.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 8),
            sep2.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep2.trailingAnchor.constraint(equalTo: trailingAnchor),
            doneBtn.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 10),
            doneBtn.centerXAnchor.constraint(equalTo: centerXAnchor),
            doneBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    func updateScrollHeight() {
        guard let docView = scrollView.documentView else { return }
        docView.layoutSubtreeIfNeeded()
        let contentH = docView.fittingSize.height
        // Calculate max scroll height based on screen
        let maxScrollH: CGFloat
        if let screen = window?.screen ?? NSScreen.main {
            // Total panel chrome: header(44) + sep(1) + input(34+8+8) + sep + done(10+20+10) = ~135
            maxScrollH = screen.visibleFrame.height - 40 - 135
        } else {
            maxScrollH = 500
        }
        scrollHeightConstraint.constant = min(max(contentH, 60), maxScrollH)
        invalidateIntrinsicContentSize()
    }

    @objc private func sendMessage() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""
        onSend(text)
    }

    @objc private func doneTapped() { onDone() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(insertNewline(_:)) { sendMessage(); return true }
        return false
    }

    // MARK: - Message Updates

    func update(messages: [ChatMessage], streamingText: String) {
        while displayedCount < messages.count {
            removeStreamingBubble()
            addBubble(messages[displayedCount])
            displayedCount += 1
        }

        if streamingText.isEmpty {
            removeStreamingBubble()
        } else if let lbl = streamingLabel {
            lbl.stringValue = streamingText
        } else {
            let (row, lbl) = bubbleRow(text: streamingText, isUser: false)
            bubbleStack.addArrangedSubview(row)
            streamingRow = row
            streamingLabel = lbl
        }

        resizePanelForChat()
    }

    private func addBubble(_ msg: ChatMessage) {
        let (row, _) = bubbleRow(text: msg.content, isUser: msg.role == .user)
        bubbleStack.addArrangedSubview(row)
    }

    private func removeStreamingBubble() {
        streamingRow?.removeFromSuperview()
        streamingRow = nil
        streamingLabel = nil
    }

    private func bubbleRow(text: String, isUser: Bool) -> (NSView, NSTextField) {
        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 12
        bubble.layer?.backgroundColor = isUser
            ? NSColor.controlAccentColor.cgColor
            : NSColor.controlBackgroundColor.cgColor
        bubble.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = isUser ? .white : .labelColor
        label.preferredMaxLayoutWidth = 280
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
        ])

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let row = hstack(spacing: 0)
        if isUser { row.addArrangedSubview(spacer); row.addArrangedSubview(bubble) }
        else       { row.addArrangedSubview(bubble); row.addArrangedSubview(spacer) }

        return (row, label)
    }

    private func resizePanelForChat() {
        updateScrollHeight()
        guard let vc = window?.contentViewController as? CheckInViewController else { return }
        vc.resizePanelToFitChat()
    }
}

// MARK: - DoneView

private final class DoneView: NSView {
    private let closeTarget: ActionTarget

    init(onClose: @escaping () -> Void) {
        self.closeTarget = ActionTarget(action: onClose)
        super.init(frame: .zero)

        let imageView = NSImageView()
        if let base = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
            imageView.image = base.withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        }
        imageView.contentTintColor = .systemGreen
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let title    = NSTextField(labelWithString: "Good awareness!")
        title.font   = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center

        let subtitle    = NSTextField(labelWithString: "You've got this.")
        subtitle.font   = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let closeBtn = NSButton(title: "Close", target: closeTarget, action: #selector(ActionTarget.fire))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let stack = vstack(spacing: 16)
        stack.alignment = .centerX
        [imageView, title, subtitle, closeBtn].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(8, after: title)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - GrowingTextInput

/// A multi-line text input that grows vertically as text wraps, up to a max height.
private final class GrowingTextInput: NSView, NSTextViewDelegate {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let placeholderLabel: NSTextField
    private let onSubmit: (String) -> Void
    private var heightConstraint: NSLayoutConstraint!
    private let minHeight: CGFloat = 34
    private let maxHeight: CGFloat = 120

    var text: String { textView.string }

    init(placeholder: String, onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        self.placeholderLabel = NSTextField(labelWithString: placeholder)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainerInset = NSSize(width: 4, height: 6)

        scrollView.documentView = textView

        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isSelectable = false

        addSubview(scrollView)
        addSubview(placeholderLabel)

        heightConstraint = heightAnchor.constraint(equalToConstant: minHeight)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            placeholderLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: minHeight / 2),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateHeight()
    }

    func textDidChange(_ notification: Notification) {
        placeholderLabel.isHidden = !textView.string.isEmpty
        updateHeight()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            let text = textView.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return true }
            onSubmit(text)
            return true
        }
        return false
    }

    private func updateHeight() {
        guard let container = textView.textContainer, let manager = textView.layoutManager else { return }
        manager.ensureLayout(for: container)
        let textHeight = manager.usedRect(for: container).height + textView.textContainerInset.height * 2
        let newHeight = min(max(textHeight, minHeight), maxHeight)
        if heightConstraint.constant != newHeight {
            heightConstraint.constant = newHeight
            scrollView.hasVerticalScroller = textHeight > maxHeight
            invalidateIntrinsicContentSize()
            // Ask the panel to resize
            if let vc = window?.contentViewController as? CheckInViewController {
                vc.view.needsLayout = true
            }
        }
    }
}

// MARK: - Helpers

/// Allows NSButton to call a Swift closure as its action target.
private final class ActionTarget: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

private func vstack(spacing: CGFloat) -> NSStackView {
    let s = NSStackView()
    s.orientation = .vertical
    s.alignment = .leading
    s.spacing = spacing
    s.translatesAutoresizingMaskIntoConstraints = false
    return s
}

/// Adds a fill-width constraint for a view inside a stack
private func fillWidth(_ view: NSView, in stack: NSStackView) {
    view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
}

private func hstack(spacing: CGFloat) -> NSStackView {
    let s = NSStackView()
    s.orientation = .horizontal
    s.alignment = .centerY
    s.spacing = spacing
    s.translatesAutoresizingMaskIntoConstraints = false
    return s
}

private func bodyLabel(_ text: String) -> NSTextField {
    let f = NSTextField(wrappingLabelWithString: text)
    f.font = .systemFont(ofSize: 15, weight: .medium)
    f.textColor = .labelColor
    f.preferredMaxLayoutWidth = 380
    return f
}

private func secondaryLabel(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = .systemFont(ofSize: 13)
    f.textColor = .secondaryLabelColor
    return f
}

private func optionButtons(_ options: [String], onSelect: @escaping (String) -> Void) -> NSStackView {
    let stack = vstack(spacing: 8)
    for opt in options {
        let btn = OptionNSButton(title: opt) { onSelect(opt) }
        stack.addArrangedSubview(btn)
        fillWidth(btn, in: stack)
    }
    return stack
}

private func makeSep() -> NSBox {
    let sep = NSBox()
    sep.boxType = .separator
    sep.translatesAutoresizingMaskIntoConstraints = false
    return sep
}

private func pin(_ view: NSView, to parent: NSView? = nil, insets: CGFloat) {
    let p = parent ?? view.superview!
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: p.topAnchor, constant: insets),
        view.bottomAnchor.constraint(equalTo: p.bottomAnchor, constant: -insets),
        view.leadingAnchor.constraint(equalTo: p.leadingAnchor, constant: insets),
        view.trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -insets),
    ])
}
