import SwiftUI

struct ShotMark: Identifiable {
    let id: UUID
    let point: ShotPoint
    let outcome: ShotOutcome
}

/// The attacking half of the pool, seen from above with the goal at the top.
/// Shows shot marks and, when `onTap` is set, reports where the user tapped.
struct PoolDiagram: View {
    var marks: [ShotMark] = []
    var markSize: CGFloat = 16
    var onTap: ((ShotPoint) -> Void)?

    /// Share of the diagram's height above the goal line, where the goal is drawn.
    private static let goalBand = 0.08
    static let aspect = PoolGeometry.width / (PoolGeometry.depth / (1 - goalBand))

    var body: some View {
        GeometryReader { geometry in
            let band = geometry.size.height * Self.goalBand
            let pool = CGRect(x: 0, y: band, width: geometry.size.width, height: geometry.size.height - band)
            let metre = pool.height / PoolGeometry.depth
            let goalWidth = pool.width * PoolGeometry.goalWidth / PoolGeometry.width

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.poolWater)
                    .frame(width: pool.width, height: pool.height)
                    .offset(y: band)

                distanceLine(metres: 2, color: .red, pool: pool, metre: metre)
                distanceLine(metres: 5, color: .yellow, pool: pool, metre: metre)
                distanceLine(metres: 6, color: .yellow, pool: pool, metre: metre, dashed: true)

                // Goal and goal line
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.6), lineWidth: 2))
                    .frame(width: goalWidth, height: band * 0.75)
                    .position(x: pool.midX, y: band - band * 0.375)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: pool.width, height: 2)
                    .position(x: pool.midX, y: pool.minY + 1)

                ForEach(marks) { mark in
                    ShotMarkView(outcome: mark.outcome, size: markSize)
                        .position(x: pool.minX + mark.point.x * pool.width, y: pool.minY + mark.point.y * pool.height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap else { return }
                let x = min(1, max(0, (location.x - pool.minX) / pool.width))
                let y = min(1, max(0, (location.y - pool.minY) / pool.height))
                onTap(ShotPoint(x: x, y: y))
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityLabel("Pool diagram with \(marks.count) shots")
    }

    private func distanceLine(metres: Double, color: Color, pool: CGRect, metre: CGFloat, dashed: Bool = false) -> some View {
        let y = pool.minY + metres * metre
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: pool.minX, y: y))
                path.addLine(to: CGPoint(x: pool.maxX, y: y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [6, 5] : []))
            Text("\(Int(metres)) m")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .position(x: pool.minX + 16, y: y - 8)
        }
    }
}

/// Each outcome has its own shape, so the chart reads without relying on colour.
struct ShotMarkView: View {
    let outcome: ShotOutcome
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch outcome {
            case .goal:
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.poolDeep, lineWidth: 1.5))
            case .saved:
                Circle()
                    .stroke(Color.white, lineWidth: size * 0.17)
                    .padding(size * 0.08)
            case .blocked:
                Rectangle()
                    .stroke(Color.white, lineWidth: size * 0.17)
                    .padding(size * 0.12)
            case .missed:
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.8, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
    }
}

/// Explains the four mark shapes.
struct ShotLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(ShotOutcome.allCases) { outcome in
                HStack(spacing: 5) {
                    ShotMarkView(outcome: outcome, size: 12)
                    Text(outcome.title)
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.poolWater, in: Capsule())
    }
}
