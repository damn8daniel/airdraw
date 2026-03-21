import Foundation
import CoreGraphics

// MARK: - Gesture Types

enum DrawingGesture: Equatable {
    case pointing   // Только указательный палец — режим курсора
    case pinching   // Щипок (большой + указательный) — рисование
    case openPalm   // Открытая ладонь — очистка холста
    case peace      // V-жест (указательный + средний) — смена цвета
    case fist       // Кулак — пауза
    case unknown    // Рука не обнаружена
}

// MARK: - Hand State

struct HandState: Equatable {
    var gesture: DrawingGesture = .unknown
    var indexTipPosition: CGPoint = .zero
    var thumbTipPosition: CGPoint = .zero
    var isDrawing: Bool = false
}

// MARK: - Drawing Stroke

struct DrawingStroke {
    var points: [CGPoint]
    var color: CGColor
    var lineWidth: CGFloat

    init(points: [CGPoint], color: CGColor, lineWidth: CGFloat) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
    }
}
