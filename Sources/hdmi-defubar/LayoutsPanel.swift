import SwiftUI
import DefubarCore

/// The "Manage layouts" window: one card per monitor set, with one row per
/// resolution variant carrying its arrangement thumbnail, its remembered
/// windows and rename, use and delete actions.
struct LayoutsPanel: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if coordinator.layoutSummaries.isEmpty {
                    Text("No saved layouts yet. Arrange your displays in System Settings or use Save current layout from the menubar.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    ForEach(coordinator.layoutSummaries) { summary in
                        SetCard(coordinator: coordinator, summary: summary)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 580, minHeight: 360)
    }
}

/// One monitor set: A name you can edit and every resolution variant seen for
/// it.
private struct SetCard: View {
    let coordinator: Coordinator
    let summary: Coordinator.LayoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EditableName(
                    label: summary.label,
                    derived: summary.activeVariant?.layout.derivedName ?? summary.label,
                    prompt: "Layout name",
                    font: .headline) { name in
                        coordinator.renameLayout(setKey: summary.id, to: name)
                    }
                if summary.isConnected {
                    Badge(text: "Connected now", tint: .accentColor)
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    coordinator.deleteLayout(setKey: summary.id)
                }
            }
            ForEach(summary.variants) { variant in
                VariantRow(coordinator: coordinator, summary: summary, variant: variant,
                           canDelete: summary.variants.count > 1)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }
}

/// One resolution combination of a set.
private struct VariantRow: View {
    let coordinator: Coordinator
    let summary: Coordinator.LayoutSummary
    let variant: Coordinator.VariantSummary
    let canDelete: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArrangementThumbnail(displays: variant.layout.displays)
                .frame(width: 160, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    EditableName(
                        label: variant.label,
                        derived: variant.layout.derivedVariantName,
                        prompt: "Variant name",
                        font: .body) { name in
                            coordinator.renameVariant(setKey: summary.id,
                                                      variantID: variant.id, to: name)
                        }
                    if variant.isActive {
                        Badge(text: "Active", tint: .secondary)
                    }
                }
                ForEach(Array(variant.layout.displays.enumerated()), id: \.offset) { _, display in
                    Text("\(display.name), \(display.pointWidth)x\(display.pointHeight) at \(Int(display.refresh.rounded())) Hz\(display.isMain ? ", main" : "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(windowSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Use") {
                        coordinator.useVariant(setKey: summary.id, variantID: variant.id)
                    }
                    .disabled(!summary.isConnected)
                    Button("Delete variant", role: .destructive) {
                        coordinator.deleteVariant(setKey: summary.id, variantID: variant.id)
                    }
                    .disabled(!canDelete)
                    if variant.windowCount > 0 {
                        Button("Forget windows") {
                            coordinator.forgetWindows(variantID: variant.id)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
    }

    private var windowSummary: String {
        guard variant.windowCount > 0, let date = variant.windowsCapturedAt else {
            return "No windows remembered yet"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: date, relativeTo: Date())
        let noun = variant.windowCount == 1 ? "window" : "windows"
        return "\(variant.windowCount) \(noun) remembered \(when)"
    }
}

/// A name field pre-filled with the current name.
///
/// Deliberately not a placeholder: A placeholder looks like text that is
/// already there while the field is in fact empty, so the first keystroke
/// appears to wipe the name and appending to it is impossible. Submitting text
/// equal to the derived name clears the custom name instead of pinning it, so
/// a later display rename still shows through.
private struct EditableName: View {
    let label: String
    let derived: String
    let prompt: String
    let font: Font
    let commit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(font)
            .focused($focused)
            .onSubmit { commitEdit() }
            .onChange(of: focused) { isFocused in
                if !isFocused { commitEdit() }
            }
            .onAppear { text = label }
            .onChange(of: label) { newLabel in
                if !focused { text = newLabel }
            }
    }

    private func commitEdit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        commit(trimmed == derived ? "" : trimmed)
        text = trimmed.isEmpty ? derived : trimmed
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.2)))
            .foregroundStyle(tint)
    }
}

/// Scaled top-view of the layout's display frames in their relative positions.
private struct ArrangementThumbnail: View {
    let displays: [SavedDisplay]

    var body: some View {
        Canvas { context, size in
            guard !displays.isEmpty else { return }
            let minX = displays.map(\.originX).min()!
            let minY = displays.map(\.originY).min()!
            let maxX = displays.map { $0.originX + $0.pointWidth }.max()!
            let maxY = displays.map { $0.originY + $0.pointHeight }.max()!
            let boundsW = CGFloat(maxX - minX)
            let boundsH = CGFloat(maxY - minY)
            let scale = min(size.width / boundsW, size.height / boundsH) * 0.94
            let offsetX = (size.width - boundsW * scale) / 2
            let offsetY = (size.height - boundsH * scale) / 2
            for display in displays {
                let rect = CGRect(
                    x: offsetX + CGFloat(display.originX - minX) * scale,
                    y: offsetY + CGFloat(display.originY - minY) * scale,
                    width: CGFloat(display.pointWidth) * scale,
                    height: CGFloat(display.pointHeight) * scale)
                    .insetBy(dx: 1.5, dy: 1.5)
                let path = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(path, with: .color(display.isMain
                    ? Color.accentColor.opacity(0.85)
                    : Color.secondary.opacity(0.45)))
                context.stroke(path, with: .color(.secondary), lineWidth: 1)
            }
        }
    }
}
