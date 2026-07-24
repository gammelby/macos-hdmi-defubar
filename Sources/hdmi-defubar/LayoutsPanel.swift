import SwiftUI
import DefubarCore

/// The "Manage layouts" window: one card per saved layout with rename,
/// arrangement thumbnail, restore and delete.
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
                        LayoutCard(coordinator: coordinator, summary: summary)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 300)
    }
}

private struct LayoutCard: View {
    let coordinator: Coordinator
    let summary: Coordinator.LayoutSummary
    @State private var name: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArrangementThumbnail(displays: summary.layout.displays)
                .frame(width: 160, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField(summary.layout.derivedName, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .onSubmit {
                            coordinator.renameLayout(setKey: summary.id, to: name)
                        }
                    if summary.isConnected {
                        Text("Connected now")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                ForEach(summary.layout.displays, id: \.fingerprint.matchKey) { display in
                    Text("\(display.name), \(display.pointWidth)x\(display.pointHeight) at \(Int(display.refresh.rounded())) Hz\(display.isMain ? ", main" : "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Restore") { coordinator.restoreSavedLayout() }
                        .disabled(!summary.isConnected)
                    Button("Delete", role: .destructive) {
                        coordinator.deleteLayout(setKey: summary.id)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        .onAppear { name = summary.layout.customName ?? "" }
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
