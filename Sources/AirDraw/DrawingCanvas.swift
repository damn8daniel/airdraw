import SwiftUI
import AppKit

// MARK: - Canvas Model

final class DrawingCanvasModel: ObservableObject {

    @Published var completedStrokes: [DrawingStroke] = []
    @Published var activePoints: [CGPoint] = []
    @Published var currentColor: Color = .red
    @Published var lineWidth: CGFloat = 5.0
    @Published var currentColorIndex: Int = 0

    private var strokeActive = false

    let palette: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .white
    ]

    // MARK: Stroke Control

    func startStroke(at point: CGPoint) {
        activePoints = [point]
        strokeActive = true
    }

    func continueStroke(at point: CGPoint) {
        guard strokeActive else { return }
        if let last = activePoints.last {
            let d = hypot(point.x - last.x, point.y - last.y)
            guard d > 1.5 else { return }
        }
        activePoints.append(point)
    }

    func endStroke() {
        guard strokeActive, activePoints.count >= 2 else {
            strokeActive = false
            activePoints = []
            return
        }
        let cgColor = NSColor(currentColor).cgColor
        let stroke = DrawingStroke(points: activePoints, color: cgColor, lineWidth: lineWidth)
        completedStrokes.append(stroke)
        activePoints = []
        strokeActive = false
    }

    func cancelStroke() {
        strokeActive = false
        activePoints = []
    }

    func clearCanvas() {
        completedStrokes = []
        activePoints = []
        strokeActive = false
    }

    func undoLast() {
        if !completedStrokes.isEmpty {
            completedStrokes.removeLast()
        }
    }

    func cycleColor() {
        currentColorIndex = (currentColorIndex + 1) % palette.count
        currentColor = palette[currentColorIndex]
    }

    var isDrawing: Bool { strokeActive }
}

// MARK: - Canvas View

struct DrawingCanvasView: View {
    @ObservedObject var model: DrawingCanvasModel

    var body: some View {
        Canvas { ctx, size in
            for stroke in model.completedStrokes {
                renderStroke(stroke.points, color: Color(cgColor: stroke.color),
                             width: stroke.lineWidth, in: ctx, size: size)
            }
            if model.activePoints.count >= 2 {
                let cgColor = NSColor(model.currentColor).cgColor
                renderStroke(model.activePoints, color: Color(cgColor: cgColor),
                             width: model.lineWidth, in: ctx, size: size)
            }
        }
    }

    private func renderStroke(_ pts: [CGPoint], color: Color, width: CGFloat,
                               in ctx: GraphicsContext, size: CGSize) {
        guard pts.count >= 2 else { return }

        var path = Path()
        path.move(to: pts[0])

        if pts.count == 2 {
            path.addLine(to: pts[1])
        } else {
            for i in 1..<pts.count - 1 {
                let mid = CGPoint(
                    x: (pts[i].x + pts[i + 1].x) / 2,
                    y: (pts[i].y + pts[i + 1].y) / 2
                )
                path.addQuadCurve(to: mid, control: pts[i])
            }
            path.addLine(to: pts[pts.count - 1])
        }

        ctx.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }
}
