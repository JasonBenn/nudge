import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role {
        case user, assistant
    }
}

struct ChatView: View {
    let messages: [ChatMessage]
    let streamingText: String
    let onSend: (String) -> Void
    let onDone: () -> Void

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                        if !streamingText.isEmpty {
                            MessageBubble(message: ChatMessage(role: .assistant, content: streamingText))
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: streamingText) {
                    proxy.scrollTo("bottom")
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Reply...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .onSubmit(sendMessage)
                    .padding(.vertical, 8)

                Button("Send") {
                    sendMessage()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button("Done") {
                onDone()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.vertical, 10)
        }
        .onAppear { inputFocused = true }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        onSend(text)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(isUser ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isUser ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
