import SwiftUI

/// A left-to-right, top-to-bottom wrapping layout for variable-width pills
/// (filter chips). `LazyVGrid` can't do this — its columns are fixed-width
/// (PLAN.md §6.2). iOS 16+, zero dependencies.
struct WrapLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrangeRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    // MARK: - Row arrangement

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        let items: [RowItem]
        let width: CGFloat
        let height: CGFloat
    }

    private func arrangeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current: [RowItem] = []
        var currentWidth: CGFloat = 0

        func flush() {
            guard !current.isEmpty else { return }
            let width = current.reduce(CGFloat(0)) { $0 + $1.size.width } + CGFloat(max(0, current.count - 1)) * horizontalSpacing
            let height = current.map(\.size.height).max() ?? 0
            rows.append(Row(items: current, width: width, height: height))
            current = []
            currentWidth = 0
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let additional = currentWidth == 0 ? size.width : size.width + horizontalSpacing
            if maxWidth.isFinite, currentWidth + additional > maxWidth, !current.isEmpty {
                flush()
            }
            current.append(RowItem(subview: subview, size: size))
            currentWidth += (currentWidth == 0 ? size.width : size.width + horizontalSpacing)
        }
        flush()
        return rows
    }
}
