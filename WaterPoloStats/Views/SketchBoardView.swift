import SwiftUI

/// A whole pool to draw plays on, with a few brush colours and sizes. Boards are saved with the game.
struct SketchBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var game: Game

    @State private var strokes: [SketchStroke] = []
    @State private var current: SketchStroke?
    @State private var colorIndex = 1
    @State private var brushSize = 5.0
    @State private var sharedImage: SharedImage?

    struct SharedImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    static let colors: [(name: String, color: Color)] = [
        ("Black", .black), ("Red", .red), ("Blue", Color(red: 0.1, green: 0.2, blue: 0.9)), ("Green", Color(red: 0.0, green: 0.55, blue: 0.2)),
    ]
    private static let sizes: [Double] = [2, 5, 10, 15]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Sketch Board") {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            } trailing: {
                Button("Share", systemImage: "square.and.arrow.up", action: share)
                    .labelStyle(.iconOnly)
                Button("Save Board") {
                    game.sketches.append(Sketch(strokes: strokes))
                }
                .disabled(strokes.isEmpty)
                Button("Clear Board") { strokes = [] }
                    .disabled(strokes.isEmpty)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    GroupLabel(title: "Brush color")
                    LazyVGrid(columns: [GridItem(.fixed(72)), GridItem(.fixed(72))], spacing: 6) {
                        ForEach(Self.colors.indices, id: \.self) { index in
                            Button { colorIndex = index } label: {
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Self.colors[index].color)
                                        .frame(width: 12, height: 12)
                                    Text(Self.colors[index].name)
                                }
                            }
                            .buttonStyle(GlossButtonStyle(color: Color(white: 0.2), selected: colorIndex == index, height: 40))
                        }
                    }
                }
                .frame(width: 150)
                VStack(spacing: 4) {
                    GroupLabel(title: "Brush size")
                    LazyVGrid(columns: [GridItem(.fixed(72)), GridItem(.fixed(72))], spacing: 6) {
                        ForEach(Self.sizes, id: \.self) { size in
                            Button("\(Int(size))") { brushSize = size }
                                .buttonStyle(GlossButtonStyle(color: Color(white: 0.2), selected: brushSize == size, height: 40))
                        }
                    }
                }
                .frame(width: 150)

                savedBoards
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            board
                .padding(16)
        }
        .background(Theme.chrome.ignoresSafeArea())
        .sheet(item: $sharedImage) { ActivityView(items: [$0.image]) }
    }

    private var savedBoards: some View {
        Group {
            if game.sketches.isEmpty {
                Text("No saved sketch boards")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(game.sketches) { sketch in
                            Button { strokes = sketch.strokes } label: {
                                SketchCanvas(strokes: sketch.strokes, lineScale: 0.18)
                                    .frame(width: 126, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Saved board from \(sketch.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .overlay(alignment: .topTrailing) {
                                Button("Delete board", systemImage: "xmark.circle.fill") {
                                    game.sketches.removeAll { $0.id == sketch.id }
                                }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .buttonStyle(.plain)
                                .padding(3)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
    }

    private var board: some View {
        GeometryReader { geometry in
            let size = geometry.size
            SketchCanvas(strokes: strokes + (current.map { [$0] } ?? []))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = ShotPoint(
                                x: min(1, max(0, value.location.x / size.width)),
                                y: min(1, max(0, value.location.y / size.height))
                            )
                            if current == nil { current = SketchStroke(color: colorIndex, width: brushSize, points: []) }
                            current?.points.append(point)
                        }
                        .onEnded { _ in
                            if let current { strokes.append(current) }
                            current = nil
                        }
                )
        }
        .aspectRatio(SketchCanvas.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Sketch board. Drag to draw on the pool.")
    }

    private func share() {
        let renderer = ImageRenderer(content: SketchCanvas(strokes: strokes).frame(width: 1200, height: 1200 / SketchCanvas.aspect))
        renderer.scale = 1
        if let image = renderer.uiImage {
            sharedImage = SharedImage(image: image)
        }
    }
}

/// The full pool, seen from above with a goal at each end, with strokes drawn over it.
struct SketchCanvas: View {
    static let length = 25.0
    static let aspect = CGFloat(length / PoolGeometry.width)

    let strokes: [SketchStroke]
    /// Thumbnails draw thinner lines.
    var lineScale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let metre = size.width / Self.length
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.poolWater))

            func line(at x: CGFloat, _ color: Color, dash: [CGFloat] = [], width: CGFloat = 2) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * max(lineScale, 0.5), dash: dash))
            }
            for edge in [0.0, 1.0] {
                // Distances are measured from each goal line.
                func x(_ metres: Double) -> CGFloat { edge == 0 ? metres * metre : size.width - metres * metre }
                line(at: x(2), .red)
                line(at: x(5), .yellow)
                line(at: x(6), .yellow, dash: [6, 5])
                let goalHeight = size.height * PoolGeometry.goalWidth / PoolGeometry.width
                let goal = CGRect(x: edge == 0 ? 0 : size.width - metre * 0.6, y: (size.height - goalHeight) / 2, width: metre * 0.6, height: goalHeight)
                context.fill(Path(goal), with: .color(.white.opacity(0.85)))
                context.stroke(Path(goal), with: .color(.poolDeep), lineWidth: 1.5 * max(lineScale, 0.5))
            }
            line(at: size.width / 2, .white, width: 3)

            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                if stroke.points.count == 1 {
                    path.addLine(to: CGPoint(x: first.x * size.width + 0.1, y: first.y * size.height))
                }
                let color = SketchBoardView.colors[min(max(stroke.color, 0), SketchBoardView.colors.count - 1)].color
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, stroke.width * lineScale), lineCap: .round, lineJoin: .round))
            }
        }
    }
}
