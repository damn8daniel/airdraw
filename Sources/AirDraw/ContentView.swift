import SwiftUI
import AppKit

struct ContentView: View {

    @StateObject private var camera  = CameraManager()
    @StateObject private var tracker = HandTracker()
    @StateObject private var canvas  = DrawingCanvasModel()

    @State private var canvasSize: CGSize = CGSize(width: 1280, height: 720)
    @State private var showCamera: Bool = true
    @State private var cameraOpacity: Double = 0.35
    @State private var showSkeleton: Bool = true
    @State private var statusMsg: String = "Покажите руку камере"

    // Для определения удержания жеста
    @State private var lastGesture: DrawingGesture = .unknown
    @State private var gestureTimer: Timer? = nil
    @State private var wasDrawing: Bool = false

    // Для сохранения
    @State private var showingSavePanel: Bool = false

    var body: some View {
        ZStack {
            // ── Фон ──────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            // ── Камера ───────────────────────────────────────────
            if showCamera, let frame = camera.currentFrame {
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(cameraOpacity)
                    .ignoresSafeArea()
            }

            // ── Холст рисования ──────────────────────────────────
            GeometryReader { geo in
                DrawingCanvasView(model: canvas)
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { canvasSize = $0 }
            }

            // ── Скелет руки ──────────────────────────────────────
            if showSkeleton && !tracker.skeletonPoints.isEmpty {
                SkeletonOverlay(lines: tracker.skeletonPoints, size: canvasSize)
            }

            // ── Курсор ───────────────────────────────────────────
            if tracker.handState.gesture != .unknown {
                CursorView(
                    position: toScreen(tracker.handState.indexTipPosition),
                    isDrawing: tracker.handState.isDrawing,
                    color: canvas.currentColor
                )
            }

            // ── UI Оверлей ───────────────────────────────────────
            VStack(spacing: 0) {
                TopBar(
                    canvas: canvas,
                    showCamera: $showCamera,
                    cameraOpacity: $cameraOpacity,
                    showSkeleton: $showSkeleton,
                    onSave: saveImage,
                    onUndo: { canvas.undoLast() }
                )
                Spacer()
                BottomBar(status: statusMsg)
            }
        }
        .onAppear(perform: setup)
        .onChange(of: tracker.handState) { state in
            handleState(state)
        }
        .onKeyPress(.z, modifiers: .command) {
            canvas.undoLast()
            return .handled
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Setup

    private func setup() {
        camera.onFrame = { [weak tracker] buf in
            tracker?.processFrame(buf)
        }
        camera.start()
    }

    // MARK: - Coordinate Mapping

    private func toScreen(_ normalized: CGPoint) -> CGPoint {
        CGPoint(
            x: normalized.x * canvasSize.width,
            y: normalized.y * canvasSize.height
        )
    }

    // MARK: - Gesture Handling

    private func handleState(_ state: HandState) {
        let pos = toScreen(state.indexTipPosition)

        switch state.gesture {

        case .pinching:
            cancelGestureTimer()
            if !wasDrawing {
                canvas.startStroke(at: pos)
                wasDrawing = true
            } else {
                canvas.continueStroke(at: pos)
            }
            statusMsg = "Рисование..."

        case .pointing:
            cancelGestureTimer()
            if wasDrawing {
                canvas.endStroke()
                wasDrawing = false
            }
            statusMsg = "Режим курсора (щипок = рисовать)"

        case .openPalm:
            endDrawingIfNeeded()
            scheduleGesture(.openPalm, delay: 1.5) {
                canvas.clearCanvas()
                statusMsg = "Холст очищен!"
            }
            statusMsg = "Удержите ладонь для очистки..."

        case .peace:
            endDrawingIfNeeded()
            scheduleGesture(.peace, delay: 1.2) {
                canvas.cycleColor()
                statusMsg = "Цвет: \(canvas.colorName)"
            }
            statusMsg = "Удержите V-жест для смены цвета..."

        case .fist:
            endDrawingIfNeeded()
            cancelGestureTimer()
            statusMsg = "Пауза"

        case .unknown:
            endDrawingIfNeeded()
            cancelGestureTimer()
            statusMsg = "Покажите руку камере"
        }
    }

    private func endDrawingIfNeeded() {
        if wasDrawing {
            canvas.endStroke()
            wasDrawing = false
        }
    }

    private func scheduleGesture(_ gesture: DrawingGesture, delay: TimeInterval, action: @escaping () -> Void) {
        guard gesture != lastGesture else { return }
        lastGesture = gesture
        cancelGestureTimer()
        gestureTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            action()
            lastGesture = .unknown
        }
    }

    private func cancelGestureTimer() {
        gestureTimer?.invalidate()
        gestureTimer = nil
        if lastGesture != .pinching {
            lastGesture = .unknown
        }
    }

    // MARK: - Save

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "AirDraw.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            renderToImage(url: url)
        }
    }

    private func renderToImage(url: URL) {
        let size = canvasSize
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))

        for stroke in canvas.completedStrokes {
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = stroke.lineWidth
            guard stroke.points.count >= 2 else { continue }
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() { path.line(to: pt) }
            NSColor(cgColor: stroke.color)?.setStroke()
            path.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Top Bar

private struct TopBar: View {
    @ObservedObject var canvas: DrawingCanvasModel
    @Binding var showCamera: Bool
    @Binding var cameraOpacity: Double
    @Binding var showSkeleton: Bool
    let onSave: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Палитра цветов
            HStack(spacing: 6) {
                ForEach(0..<canvas.palette.count, id: \.self) { i in
                    Circle()
                        .fill(canvas.palette[i])
                        .frame(width: canvas.currentColorIndex == i ? 28 : 20,
                               height: canvas.currentColorIndex == i ? 28 : 20)
                        .overlay(Circle().stroke(Color.white.opacity(0.8),
                                                 lineWidth: canvas.currentColorIndex == i ? 2.5 : 0))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .onTapGesture {
                            canvas.currentColorIndex = i
                            canvas.currentColor = canvas.palette[i]
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .cornerRadius(20)

            // Толщина линии
            HStack(spacing: 6) {
                Image(systemName: "pencil.tip")
                    .foregroundStyle(.secondary)
                Slider(value: $canvas.lineWidth, in: 2...25)
                    .frame(width: 90)
                Text("\(Int(canvas.lineWidth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            Spacer()

            // Управление
            HStack(spacing: 8) {
                ControlButton(icon: "arrow.uturn.backward", label: "Отмена", action: onUndo)
                ControlButton(icon: "trash", label: "Очистить", isDestructive: true) {
                    canvas.clearCanvas()
                }
                ControlButton(icon: "square.and.arrow.down", label: "Сохранить", action: onSave)

                Divider().frame(height: 24)

                Toggle(isOn: $showCamera) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13))
                }
                .toggleStyle(.button)
                .help("Показать/скрыть камеру")

                if showCamera {
                    Slider(value: $cameraOpacity, in: 0...1)
                        .frame(width: 70)
                        .help("Прозрачность камеры")
                }

                Toggle(isOn: $showSkeleton) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13))
                }
                .toggleStyle(.button)
                .help("Показать скелет руки")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct ControlButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isDestructive ? .red : .primary)
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}

// MARK: - Bottom Bar

private struct BottomBar: View {
    let status: String

    var body: some View {
        HStack {
            GestureGuide()
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct GestureGuide: View {
    private let items: [(String, String)] = [
        ("☝️", "Курсор"),
        ("🤏", "Рисовать"),
        ("✌️", "Цвет"),
        ("✋", "Очистить"),
        ("✊", "Пауза")
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.0) { emoji, label in
                VStack(spacing: 2) {
                    Text(emoji).font(.title3)
                    Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Cursor View

struct CursorView: View {
    let position: CGPoint
    let isDrawing: Bool
    let color: Color

    var body: some View {
        ZStack {
            if isDrawing {
                Circle()
                    .fill(color.opacity(0.8))
                    .frame(width: 14, height: 14)
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
            } else {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
            }
        }
        .position(position)
        .animation(.linear(duration: 0.04), value: position)
    }
}

// MARK: - Skeleton Overlay

struct SkeletonOverlay: View {
    let lines: [(CGPoint, CGPoint)]
    let size: CGSize

    var body: some View {
        Canvas { ctx, _ in
            for (a, b) in lines {
                let pa = CGPoint(x: a.x * size.width, y: a.y * size.height)
                let pb = CGPoint(x: b.x * size.width, y: b.y * size.height)
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                ctx.stroke(path, with: .color(.green.opacity(0.65)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

                let dot = CGRect(x: pa.x - 3, y: pa.y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dot), with: .color(.green.opacity(0.9)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Helpers

extension DrawingCanvasModel {
    var colorName: String {
        let names = ["Красный", "Оранжевый", "Жёлтый", "Зелёный",
                     "Голубой", "Синий", "Фиолетовый", "Розовый", "Белый"]
        return names.indices.contains(currentColorIndex) ? names[currentColorIndex] : "Цвет"
    }
}
