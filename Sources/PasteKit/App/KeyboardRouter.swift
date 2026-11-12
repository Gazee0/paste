import AppKit
import Carbon.HIToolbox

/// Window-local keyboard behavior for the palette.
///
/// This is an `NSEvent` monitor rather than SwiftUI `onKeyPress` because ↑↓, Space and Return
/// have to be taken before the focused search field consumes them. The search field keeps all
/// ordinary typing; only the keys listed here are intercepted.
@MainActor
final class KeyboardRouter {
    private let model: AppModel
    private let panel: NSPanel
    private let onOpenSettings: () -> Void
    private var monitor: Any?

    /// Physical number-row key codes, so quick-paste works regardless of the active keyboard
    /// layout (charactersIgnoringModifiers can be something other than "1"…"9").
    private static let digitKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1,
        UInt16(kVK_ANSI_2): 2,
        UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4,
        UInt16(kVK_ANSI_5): 5,
        UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7,
        UInt16(kVK_ANSI_8): 8,
        UInt16(kVK_ANSI_9): 9,
    ]

    init(model: AppModel, panel: NSPanel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.panel = panel
        self.onOpenSettings = onOpenSettings
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard NSApp.isActive,
              panel.isKeyWindow,
              panel.attachedSheet == nil,
              NSApp.modalWindow == nil else { return false }

        // Never steal arrows/return from an active input-method composition.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }

        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad])

        // Escape leaves editing, then multi-select, then clears the query, then hides. It never
        // closes the preview on its own; use the top-bar eye toggle / Space / ⇧Space for that.
        if event.keyCode == 53 {
            if model.isEditingPreview {
                model.cancelEditing()
            } else if model.isMultiSelecting {
                model.toggleMultiSelect()
            } else if !model.searchQuery.isEmpty {
                model.searchQuery = ""
                model.refocusSearch()
            } else if model.isWindowPinned {
                // A pinned palette is deliberately persistent: Escape must not hide it.
                model.refocusSearch()
            } else {
                model.requestHide()
            }
            return true
        }

        // While editing preview text, the text editor owns every other key.
        if model.isEditingPreview { return false }

        // Tab is the global switch between clipboard history and quick snippets.
        if event.keyCode == 48, flags.isEmpty || flags == .shift {
            guard !event.isARepeat else { return true }
            model.switchTab()
            return true
        }

        // The preview's read-only NSTextView owns arrow keys, selection, and ⌘C/⌘A while it has
        // the keyboard. Only Escape (above) remains a palette shortcut.
        if panel.firstResponder is PreviewTextView { return false }

        // Shift+Space is the preview shortcut when the search field needs plain Space for
        // typing multi-word queries.
        if event.keyCode == 49, flags == .shift {
            guard !event.isARepeat else { return true }
            model.togglePreview()
            return true
        }

        // Left/right switch the kind filter while the search query is empty. With a query,
        // arrows keep their normal text-caret behavior; clear the query (Esc) to switch again.
        if flags.isEmpty, !model.isSearching {
            if event.keyCode == 123 { // ←
                if model.activeTab == .quick {
                    // ← moves focus from the snippet list into the folder sidebar.
                    model.setQuickFocusZone(.folders)
                } else {
                    model.cycleHistoryFilter(by: -1)
                }
                return true
            }
            if event.keyCode == 124 { // →
                if model.activeTab == .quick {
                    // → returns focus from the folder sidebar to the snippet list.
                    model.setQuickFocusZone(.list)
                } else {
                    model.cycleHistoryFilter(by: 1)
                }
                return true
            }
        }

        // Command shortcuts.
        if flags == .command {
            if event.keyCode == UInt16(kVK_ANSI_LeftBracket) { // [
                if model.activeTab == .quick {
                    model.cycleQuickFolder(by: -1)
                } else {
                    model.cycleHistoryFilter(by: -1)
                }
                return true
            }
            if event.keyCode == UInt16(kVK_ANSI_RightBracket) { // ]
                if model.activeTab == .quick {
                    model.cycleQuickFolder(by: 1)
                } else {
                    model.cycleHistoryFilter(by: 1)
                }
                return true
            }
            if event.keyCode == 43 { // ,
                onOpenSettings()
                return true
            }
            if event.keyCode == 13 { // W
                model.requestHide()
                return true
            }
            if event.keyCode == 3 { // F
                model.refocusSearch()
                return true
            }
            if let number = Self.digitKeyCodes[event.keyCode], !event.isARepeat {
                if model.activeTab == .quick {
                    let rows = model.quickFilteredSnippets
                    if number <= rows.count {
                        model.pasteQuick(rows[number - 1])
                    }
                } else {
                    let rows = model.filteredItems
                    if number <= rows.count {
                        model.paste(rows[number - 1])
                    }
                }
                return true
            }
        }

        guard flags.isEmpty else { return false }

        switch event.keyCode {
        case 126: // ↑
            model.moveSelection(by: -1)
            return true
        case 125: // ↓
            model.moveSelection(by: 1)
            return true
        case 49: // Space toggles preview while the query is empty; otherwise it types a space.
            if model.searchQuery.isEmpty {
                guard !event.isARepeat else { return true }
                model.togglePreview()
                return true
            }
            return false
        case 36, 76: // ↩ / keypad enter
            guard !event.isARepeat else { return true }
            if model.activeTab == .quick, model.quickFocusZone == .folders {
                // Return focus to the list rather than pasting while the folder sidebar owns
                // the keyboard.
                model.setQuickFocusZone(.list)
                return true
            }
            if model.isMultiSelecting {
                return true
            }
            model.pasteSelected()
            return true
        case 51, 117: // ⌫ / ⌦
            if model.isMultiSelecting, !model.checkedIDs.isEmpty {
                model.deleteChecked()
                return true
            }
            return false
        default:
            return false
        }
    }
}
