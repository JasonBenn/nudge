import AppKit

// MARK: - CheckInViewController

final class CheckInViewController: NSViewController {
    private let suggestions: [String]
    private unowned let coordinator: CheckInCoordinator
    private let onComplete: (String) -> Void
    private let onCloseAll: () -> Void
    private let onAutoClose: () -> Void
    private let onDismiss: () -> Void

    private weak var panel: FloatingPanel?
    private let contentContainer = NSView()
    private var currentChild: NSView?
    private weak var chatViewRef: AppKitChatView?
    private var timerLabel: NSTextField!

    init(suggestions: [String],
         coordinator: CheckInCoordinator,
         onComplete: @escaping (String) -> Void,
         onCloseAll: @escaping () -> Void,
         onAutoClose: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.suggestions = suggestions
        self.coordinator = coordinator
        self.onComplete = onComplete
        self.onCloseAll = onCloseAll
        self.onAutoClose = onAutoClose
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
        updateTimerDisplay()
        coordinator.onCountdownTick = { [weak self] in
            guard let self else { return }
            self.updateTimerDisplay()
            if (self.coordinator.sessionRemaining ?? 0) <= 0 {
                self.onAutoClose()
            }
        }
        showSuggestions()
    }

    private func updateTimerDisplay() {
        let remaining = coordinator.sessionRemaining ?? 0
        let secs = max(0, Int(remaining))
        let mins = secs / 60
        let s = secs % 60
        timerLabel.stringValue = String(format: "%d:%02d", mins, s)
        timerLabel.textColor = remaining <= 30 ? .systemRed : .tertiaryLabelColor
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let timer = NSTextField(labelWithString: "0:00")
        timer.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timer.textColor = .tertiaryLabelColor
        timer.translatesAutoresizingMaskIntoConstraints = false
        self.timerLabel = timer

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
        header.addSubview(label)
        header.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            timer.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            timer.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            label.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            closeBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),
            closeBtn.heightAnchor.constraint(equalToConstant: 20),
        ])
        return header
    }

    @objc private func closePanel() {
        onDismiss()
    }

    // MARK: - Suggestions

    private func showSuggestions() {
        showChild(SuggestionsView(
            suggestions: suggestions,
            onSelect: { [weak self] choice in
                self?.onComplete(choice)
            },
            onCloseAll: { [weak self] in
                self?.onCloseAll()
            },
            onCloseAllAndDiscuss: { [weak self] in
                self?.coordinator.closeTabsOnly()
                self?.showChat()
            }
        ))
    }

    private func showChat() {
        // Stop countdown — user is actively engaged
        coordinator.stopMenuBarCountdown()
        timerLabel.stringValue = ""

        coordinator.chatMessages = []
        coordinator.streamingText = ""

        let v = AppKitChatView(
            onSend: { [weak self] text in self?.coordinator.sendChatMessage(text) },
            onSubmitAndDismiss: { [weak self] text in
                guard let self else { return }
                self.coordinator.chatMessages.append(ChatMessage(role: .user, content: text))
                self.coordinator.updateEvent()
                self.onDismiss()
            }
        )
        chatViewRef = v
        v.update(messages: coordinator.chatMessages, streamingText: coordinator.streamingText)
        showChild(v)
    }

    private func showChild(_ child: NSView) {
        currentChild?.removeFromSuperview()
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

    // MARK: - Public

    func chatStateChanged(messages: [ChatMessage], streamingText: String) {
        chatViewRef?.update(messages: messages, streamingText: streamingText)
    }

    func resizePanelToFitChat() {
        guard let child = currentChild else { return }
        resizePanel(for: child, animate: false)
    }

    private func resizePanel(for child: NSView, animate: Bool = true) {
        child.layoutSubtreeIfNeeded()
        let maxH = maxPanelHeight()
        let totalH = min(44 + 1 + child.fittingSize.height, maxH)
        guard let p = panel else { return }
        let r = p.frame
        let newH = max(totalH, 200)
        let newY = r.origin.y + r.height - newH
        p.setFrame(NSRect(x: r.origin.x, y: newY, width: 420, height: newH),
                   display: true, animate: animate)
    }

    private func maxPanelHeight() -> CGFloat {
        guard let screen = panel?.screen ?? NSScreen.main else { return 700 }
        return screen.visibleFrame.height - 40
    }
}

// MARK: - SuggestionsView

private final class SuggestionsView: NSView {
    private let onSelect: (String) -> Void
    private let onCloseAll: () -> Void
    private let onCloseAllAndDiscuss: () -> Void
    private var textInput: GrowingTextInput!
    private var submitTarget: ActionTarget!
    private var closeAllTarget: ActionTarget!
    private var discussTarget: ActionTarget!

    init(suggestions: [String], onSelect: @escaping (String) -> Void, onCloseAll: @escaping () -> Void, onCloseAllAndDiscuss: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onCloseAll = onCloseAll
        self.onCloseAllAndDiscuss = onCloseAllAndDiscuss
        super.init(frame: .zero)

        let stack = vstack(spacing: 16)

        let views: [NSView] = [
            bodyLabel("What would you rather do instead?"),
            suggestionButtons(suggestions),
            customInputSection(),
            actionButtons(),
        ]
        for v in views {
            stack.addArrangedSubview(v)
            fillWidth(v, in: stack)
        }

        addSubview(stack)
        pin(stack, insets: 20)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func suggestionButtons(_ suggestions: [String]) -> NSStackView {
        let stack = vstack(spacing: 8)
        if suggestions.isEmpty {
            stack.addArrangedSubview(secondaryLabel("No history yet — type something below"))
        } else {
            for choice in suggestions.prefix(8) {
                let btn = OptionNSButton(title: choice) { [weak self] in self?.onSelect(choice) }
                stack.addArrangedSubview(btn)
                fillWidth(btn, in: stack)
            }
        }
        return stack
    }

    private func customInputSection() -> NSView {
        textInput = GrowingTextInput(placeholder: "Something else...", onSubmit: { [weak self] text in
            self?.onSelect(text)
        })

        submitTarget = ActionTarget { [weak self] in
            guard let self else { return }
            let text = self.textInput.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            self.onSelect(text)
        }

        let submitBtn = NSButton(title: "Submit", target: submitTarget, action: #selector(ActionTarget.fire))
        submitBtn.bezelStyle = .rounded
        submitBtn.translatesAutoresizingMaskIntoConstraints = false

        let row = hstack(spacing: 8)
        row.addArrangedSubview(textInput)
        row.addArrangedSubview(submitBtn)
        textInput.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func actionButtons() -> NSView {
        closeAllTarget = ActionTarget { [weak self] in self?.onCloseAll() }
        let closeBtn = NSButton(title: "Close all", target: closeAllTarget, action: #selector(ActionTarget.fire))
        closeBtn.bezelStyle = .rounded
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        discussTarget = ActionTarget { [weak self] in self?.onCloseAllAndDiscuss() }
        let discussBtn = NSButton(title: "Close all & discuss", target: discussTarget, action: #selector(ActionTarget.fire))
        discussBtn.bezelStyle = .rounded
        discussBtn.translatesAutoresizingMaskIntoConstraints = false

        let row = hstack(spacing: 8)
        row.addArrangedSubview(closeBtn)
        row.addArrangedSubview(discussBtn)
        return row
    }
}

// MARK: - AppKitChatView

private final class AppKitChatView: NSView, NSTextFieldDelegate {
    private let onSend: (String) -> Void
    private let onSubmitAndDismiss: (String) -> Void

    private let scrollView = NSScrollView()
    private let bubbleStack: NSStackView
    private let inputField = NSTextField()

    private var displayedCount = 0
    private var streamingLabel: NSTextField?
    private var streamingRow: NSView?
    private var scrollHeightConstraint: NSLayoutConstraint!

    init(onSend: @escaping (String) -> Void, onSubmitAndDismiss: @escaping (String) -> Void) {
        self.onSend = onSend
        self.onSubmitAndDismiss = onSubmitAndDismiss
        self.bubbleStack = vstack(spacing: 10)
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
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

        inputField.placeholderString = "Reply..."
        inputField.bezelStyle = .roundedBezel
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false

        let sendBtn = NSButton(title: "Submit", target: self, action: #selector(sendMessage))
        sendBtn.bezelStyle = .rounded
        sendBtn.translatesAutoresizingMaskIntoConstraints = false

        let dismissBtn = NSButton(title: "Submit & dismiss", target: self, action: #selector(submitAndDismiss))
        dismissBtn.bezelStyle = .rounded
        dismissBtn.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = hstack(spacing: 8)
        inputRow.addArrangedSubview(inputField)
        inputRow.addArrangedSubview(sendBtn)
        inputRow.addArrangedSubview(dismissBtn)
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sep = makeSep()
        [scrollView, sep, inputRow].forEach { addSubview($0) }

        scrollHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 60)
        scrollHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollHeightConstraint,
            docView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            sep.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 8),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            inputField.heightAnchor.constraint(equalToConstant: 34),
            inputRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    func updateScrollHeight() {
        guard let docView = scrollView.documentView else { return }
        docView.layoutSubtreeIfNeeded()
        let contentH = docView.fittingSize.height
        let maxScrollH: CGFloat
        if let screen = window?.screen ?? NSScreen.main {
            maxScrollH = screen.visibleFrame.height - 40 - 120
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

    @objc private func submitAndDismiss() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""
        onSubmitAndDismiss(text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(insertNewline(_:)) { sendMessage(); return true }
        return false
    }

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

// MARK: - GrowingTextInput

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
        }
    }
}

// MARK: - Helpers

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
