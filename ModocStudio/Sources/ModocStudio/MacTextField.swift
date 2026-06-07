import AppKit
import SwiftUI

/// AppKit text field — SwiftUI TextField in sheets often ignores keyboard on macOS.
struct MacTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool = true
    var autofocus: Bool = false
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = isEnabled
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.didSubmit(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.isEnabled = isEnabled

        if autofocus && context.coordinator.requestFocus {
            context.coordinator.requestFocus = false
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?
        var requestFocus = true

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        @objc func didSubmit(_ sender: NSTextField) {
            onSubmit?()
        }
    }
}
