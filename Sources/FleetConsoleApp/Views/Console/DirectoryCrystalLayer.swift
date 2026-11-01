import SwiftUI

/// The faceted substrate encodes folder containment. Filled sibling fans are
/// grouping planes, never extra dependency edges between sibling directories.
struct DirectoryCrystalLayer: View {
    let crystal: DirectoryCrystal?
    let offset: CGSize
    let selectedPath: String?
    let projectPositions: [String: CGPoint]
    let zoom: CGFloat
    let point: (CGPoint) -> CGPoint
    let select: (String) -> Void

    var body: some View {
        let nodes = crystal?.nodes ?? []
        let index = Dictionary(uniqueKeysWithValues: nodes.map { ($0.path, $0) })
        let children = Dictionary(grouping: nodes.filter { $0.parentPath != nil }, by: { $0.parentPath! })
        Canvas { context, _ in
            for parent in nodes {
                let family = (children[parent.path] ?? []).sorted {
                    atan2($0.position.y - parent.position.y, $0.position.x - parent.position.x) <
                    atan2($1.position.y - parent.position.y, $1.position.x - parent.position.x)
                }
                guard family.count >= 2 else { continue }
                for pair in zip(family, family.dropFirst()) {
                    let a = screen(parent.position)
                    let b = screen(pair.0.position)
                    let c = screen(pair.1.position)
                    guard abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) > 1 else { continue }
                    var face = Path()
                    face.move(to: a); face.addLine(to: b); face.addLine(to: c); face.closeSubpath()
                    context.fill(face, with: .color(AwarenessInk.crystalFacet))
                }
            }
            for branch in crystal?.branches ?? [] {
                guard let parent = index[branch.parent], let child = index[branch.child] else { continue }
                var path = Path()
                path.move(to: screen(parent.position)); path.addLine(to: screen(child.position))
                let selected = selectedPath == parent.path || selectedPath == child.path
                context.stroke(path, with: .color(selected ? .accentColor : AwarenessInk.crystalBranch),
                               style: StrokeStyle(lineWidth: selected ? 2 : (parent.depth == 0 ? 1.4 : 0.8), lineCap: .round))
            }
            for (path, projectPosition) in projectPositions {
                guard let directory = index[path] else { continue }
                let a = screen(directory.position)
                let b = point(projectPosition)
                if hypot(b.x - a.x, b.y - a.y) > 1 {
                    var link = Path(); link.move(to: a); link.addLine(to: b)
                    context.stroke(link, with: .color(AwarenessInk.crystalBranch), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            for node in nodes {
                let center = screen(node.position)
                let selected = selectedPath == node.path
                let radius = selected ? 8.0 : (node.depth == 0 ? 7.0 : 3.5)
                var vertex = Path()
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3
                    let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    if i == 0 { vertex.move(to: p) } else { vertex.addLine(to: p) }
                }
                vertex.closeSubpath()
                context.fill(vertex, with: .color(selected || node.depth == 0 ? .accentColor : AwarenessInk.crystalVertex))
                if (node.depth == 0 || selected || (zoom >= 0.5 && node.depth == 1) || (zoom >= 0.85 && node.depth == 2)) && projectPositions[node.path] == nil {
                    let count = node.childDirectoryCount.map { "\($0)" } ?? "?"
                    let title = String(node.name.prefix(30)) + " · " + count
                    let text = Text(title).font(node.depth == 0 ? ConsoleFont.caption.weight(.semibold) : ConsoleFont.micro)
                        .foregroundStyle(SurfaceInk.secondary)
                    context.draw(text, at: CGPoint(x: center.x, y: center.y - 18))
                }
            }
        }
        .accessibilityLabel("Directory structure. Straight branches are observed parent–child folders; facets group their children.")
        .accessibilityIdentifier("directory.structure")
        .accessibilityChildren {
            // Virtual controls avoid hundreds of live SwiftUI card views. The
            // detail's child navigator makes every observed branch reachable.
            ForEach(nodes.prefix(100)) { node in
                Button { select(node.path) } label: {
                    Text(node.name + ", " + (node.childDirectoryCount.map { "\($0) child folders" } ?? "child count unavailable"))
                }
                .accessibilityIdentifier("directory.node." + node.path)
            }
        }
        .allowsHitTesting(false)
    }

    private func screen(_ p: CGPoint) -> CGPoint {
        point(CGPoint(x: p.x + offset.width, y: p.y + offset.height))
    }
}
