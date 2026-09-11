import SwiftUI
import ArthurKit

/// The bubble.and.pencil quick-add popover/sheet. Three options: New Task
/// (opens AddTaskSheet unchanged), Quick Capture (just switches the
/// selected tab), and New Reflection, which — per Brandon's explicit call —
/// doesn't navigate anywhere: the modal transitions in place to a small
/// inline compose box that appends straight to today's daily note, reusing
/// DailyNoteComposeBox (the same view AddNoteSheet uses) rather than a
/// second copy of that placeholder/PlainTextEditor logic.
///
/// Platform-neutral — nothing in here is actually Mac-specific. Presented
/// via `.popover` on every platform: a real anchored popover on Mac/iPad,
/// auto-adapted into a bottom sheet by SwiftUI on compact-width iPhone with
/// no extra code, which happens to be exactly the right presentation for
/// the inline New Reflection compose box on a phone screen.
struct QuickAddModal: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTab: HomeTab
    @Binding var showingAddTask: Bool
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var systemScheme

    private enum Mode {
        case menu
        case reflection
    }

    @State private var mode: Mode = .menu
    @State private var reflectionText = ""

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    private var modalWidth: CGFloat {
        #if os(macOS)
        return mode == .menu ? 220 : 260
        #else
        return mode == .menu ? 260 : 300
        #endif
    }

    var body: some View {
        Group {
            switch mode {
            case .menu: menuBody
            case .reflection: reflectionBody
            }
        }
        // 260, not 340 — with arrowEdge: .bottom the popover centers
        // horizontally on the sidebar's bubble.and.pencil button, which
        // sits close to the window's left edge; 340 pushed roughly a third
        // of the popover's width past that edge. 260 keeps it comfortably
        // within a typical sidebar-width window even fully collapsed to
        // Theme.sidebarMinWidth.
        //
        // iOS/iPadOS get wider frames (260/300, not 220/260) — the row/
        // title text inside grew from 13pt to Theme.inputFontSize (20) as
        // part of standardizing every iOS text size to the header date's
        // own size, and the narrower Mac widths started clipping/wrapping
        // that larger text.
        .frame(width: modalWidth)
        .background(Theme.background(effectiveScheme))
        .foregroundStyle(Theme.primary(effectiveScheme))
        // Reset back to the menu each time the popover is reopened, rather
        // than reopening mid-compose from a previous visit — quick-add is
        // meant to be a fast one-shot action, not a place to leave drafts
        // sitting around unlike Quick Capture's own tab.
        .onChange(of: isPresented) {
            if isPresented {
                mode = .menu
                reflectionText = ""
            }
        }
    }

    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            quickAddRow(title: "New Task", systemImage: "checkmark.circle") {
                isPresented = false
                showingAddTask = true
            }
            Divider()
            quickAddRow(title: "Quick Capture", systemImage: "bolt") {
                isPresented = false
                selectedTab = .quickCapture
            }
            Divider()
            quickAddRow(title: "New Reflection", systemImage: "moon.stars") {
                mode = .reflection
            }
        }
        .padding(.vertical, 6)
    }

    private func quickAddRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 18)
                // Mac keeps 13; iOS/iPadOS now match Theme.inputFontSize —
                // see modalWidth's comment for why the popover widened to
                // match.
                #if os(macOS)
                Text(title).font(.system(size: 13))
                #else
                Text(title).font(.system(size: Theme.inputFontSize()))
                #endif
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reflectionBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Reflection")
                #if os(macOS)
                .font(.system(size: 13, weight: .semibold))
                #else
                .font(.system(size: Theme.inputFontSize(), weight: .semibold))
                #endif
                .padding(.horizontal, 14)
            DailyNoteComposeBox(
                store: store, text: $reflectionText,
                effectiveScheme: effectiveScheme, inputFontSize: Theme.inputFontSize(), bordered: false
            )
            .frame(height: 140)
            .padding(.horizontal, 14)
            HStack {
                Spacer()
                PillButton(systemImage: "arrow.up.circle", label: "Add") {
                    store.appendToDailyNote(reflectionText)
                    isPresented = false
                }
                .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 14)
    }
}
