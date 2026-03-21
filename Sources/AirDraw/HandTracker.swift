import Vision
import AVFoundation
import CoreGraphics

final class HandTracker: ObservableObject {

    @Published var handState = HandState()
    @Published var skeletonPoints: [(CGPoint, CGPoint)] = []  // Линии скелета

    private let request = VNDetectHumanHandPoseRequest()
    private let visionQueue = DispatchQueue(label: "com.airdraw.vision", qos: .userInitiated)

    // Сглаживание (EMA — exponential moving average)
    private var smoothedIndex: CGPoint = .zero
    private var smoothedThumb: CGPoint = .zero
    private let alpha: CGFloat = 0.4  // Коэффициент сглаживания (0 = очень плавно, 1 = без сглаживания)

    private var lastProcessTime: CFTimeInterval = 0
    private let processInterval: CFTimeInterval = 1.0 / 20.0  // 20 fps для детекции

    init() {
        request.maximumHandCount = 1
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastProcessTime >= processInterval else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        visionQueue.async { [weak self] in
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([self.request])
                guard let observations = self.request.results,
                      let hand = observations.first else {
                    DispatchQueue.main.async { [weak self] in
                        self?.handState = HandState()
                        self?.skeletonPoints = []
                    }
                    return
                }
                self.updateState(from: hand)
            } catch {
                // Тихо игнорируем ошибки Vision
            }
        }
    }

    private func updateState(from observation: VNHumanHandPoseObservation) {
        guard
            let indexTip  = try? observation.recognizedPoint(.indexTip),  indexTip.confidence  > 0.3,
            let thumbTip  = try? observation.recognizedPoint(.thumbTip),  thumbTip.confidence  > 0.3,
            let middleTip = try? observation.recognizedPoint(.middleTip), middleTip.confidence > 0.2
        else {
            DispatchQueue.main.async { [weak self] in
                self?.handState = HandState()
                self?.skeletonPoints = []
            }
            return
        }

        // Vision: x∈[0,1] слева, y∈[0,1] снизу
        // Экран: флипаем y, зеркалируем x (т.к. отображаем зеркально)
        let rawIndex = CGPoint(x: 1 - indexTip.location.x, y: 1 - indexTip.location.y)
        let rawThumb = CGPoint(x: 1 - thumbTip.location.x, y: 1 - thumbTip.location.y)

        // Сглаживание
        let sIndex = smooth(current: rawIndex, prev: smoothedIndex)
        let sThumb = smooth(current: rawThumb, prev: smoothedThumb)
        smoothedIndex = sIndex
        smoothedThumb = sThumb

        let gesture = detectGesture(from: observation)
        let skeleton = buildSkeleton(from: observation)

        let newState = HandState(
            gesture: gesture,
            indexTipPosition: sIndex,
            thumbTipPosition: sThumb,
            isDrawing: gesture == .pinching
        )

        DispatchQueue.main.async { [weak self] in
            self?.handState = newState
            self?.skeletonPoints = skeleton
        }
    }

    // MARK: - Gesture Detection

    private func detectGesture(from obs: VNHumanHandPoseObservation) -> DrawingGesture {
        let minConf: Float = 0.3

        guard
            let thumbTip  = try? obs.recognizedPoint(.thumbTip),  thumbTip.confidence  > minConf,
            let indexTip  = try? obs.recognizedPoint(.indexTip),  indexTip.confidence  > minConf,
            let middleTip = try? obs.recognizedPoint(.middleTip), middleTip.confidence > minConf,
            let indexMCP  = try? obs.recognizedPoint(.indexMCP),  indexMCP.confidence  > minConf,
            let middleMCP = try? obs.recognizedPoint(.middleMCP), middleMCP.confidence > minConf,
            let wrist     = try? obs.recognizedPoint(.wrist),     wrist.confidence     > minConf
        else { return .unknown }

        // Щипок — большой и указательный близко
        let pinchDist = dist(thumbTip.location, indexTip.location)
        if pinchDist < 0.07 { return .pinching }

        // Определяем, разогнуты ли пальцы
        let indexUp  = isExtended(tip: indexTip,  base: indexMCP,  wrist: wrist)
        let middleUp = isExtended(tip: middleTip, base: middleMCP, wrist: wrist)

        var ringUp   = false
        var littleUp = false
        if let ringTip  = try? obs.recognizedPoint(.ringTip),   ringTip.confidence  > minConf,
           let ringMCP  = try? obs.recognizedPoint(.ringMCP),   ringMCP.confidence  > minConf {
            ringUp = isExtended(tip: ringTip, base: ringMCP, wrist: wrist)
        }
        if let littleTip = try? obs.recognizedPoint(.littleTip), littleTip.confidence > minConf,
           let littleMCP = try? obs.recognizedPoint(.littleMCP), littleMCP.confidence > minConf {
            littleUp = isExtended(tip: littleTip, base: littleMCP, wrist: wrist)
        }

        // Открытая ладонь — все четыре пальца разогнуты
        if indexUp && middleUp && ringUp && littleUp { return .openPalm }

        // V-жест — только указательный и средний
        if indexUp && middleUp && !ringUp && !littleUp { return .peace }

        // Указатель — только указательный
        if indexUp && !middleUp && !ringUp && !littleUp { return .pointing }

        // Кулак — ни один не разогнут
        if !indexUp && !middleUp && !ringUp && !littleUp { return .fist }

        return .unknown
    }

    private func isExtended(tip: VNRecognizedPoint, base: VNRecognizedPoint, wrist: VNRecognizedPoint) -> Bool {
        dist(tip.location, wrist.location) > dist(base.location, wrist.location) * 1.15
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Skeleton

    func buildSkeleton(from obs: VNHumanHandPoseObservation) -> [(CGPoint, CGPoint)] {
        let connections: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
            (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
            (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
            (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
            (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
            (.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP)
        ]

        var lines: [(CGPoint, CGPoint)] = []
        for (jA, jB) in connections {
            guard
                let pA = try? obs.recognizedPoint(jA), pA.confidence > 0.2,
                let pB = try? obs.recognizedPoint(jB), pB.confidence > 0.2
            else { continue }
            // Конвертируем Vision → нормализованные экранные координаты [0,1]
            let a = CGPoint(x: 1 - pA.location.x, y: 1 - pA.location.y)
            let b = CGPoint(x: 1 - pB.location.x, y: 1 - pB.location.y)
            lines.append((a, b))
        }
        return lines
    }

    // MARK: - Smoothing

    private func smooth(current: CGPoint, prev: CGPoint) -> CGPoint {
        CGPoint(
            x: alpha * current.x + (1 - alpha) * prev.x,
            y: alpha * current.y + (1 - alpha) * prev.y
        )
    }
}
