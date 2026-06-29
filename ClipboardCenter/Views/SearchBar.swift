import SwiftUI

// MARK: - SearchBar
// A compact search bar with icon, text field, and clear button.
// Designed for the popover header area.

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search clipboard history…"
    @FocusState private var isFocused: Bool
    @State private var isClicked = false

    private var showFocusRing: Bool {
        isFocused && (!text.isEmpty || isClicked)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .keyboardFocusIndicatorColor).opacity(showFocusRing ? 0.3 : 0.0), lineWidth: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    showFocusRing
                        ? Color(nsColor: .keyboardFocusIndicatorColor)
                        : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: showFocusRing ? 1 : 0.5
                )
        )
        .simultaneousGesture(TapGesture().onEnded {
            isClicked = true
        })
        .onChange(of: isFocused) { focused in
            if !focused {
                isClicked = false
            }
        }
        .animation(.easeOut(duration: 0.15), value: showFocusRing)
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = false
            }
        }
    }
}
