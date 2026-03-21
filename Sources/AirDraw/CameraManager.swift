import AVFoundation
import CoreImage
import AppKit

final class CameraManager: NSObject, ObservableObject {

    // Кадр для отображения (зеркальный, для UI)
    @Published var currentFrame: NSImage?

    // Колбэк для Vision — получает оригинальный (не зеркальный) буфер
    var onFrame: ((CMSampleBuffer) -> Void)?

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.airdraw.session", qos: .userInitiated)
    private let context = CIContext()

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .hd1280x720

            // Выбираем фронтальную или встроенную камеру
            let device: AVCaptureDevice?
            if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                device = front
            } else {
                device = AVCaptureDevice.default(for: .video)
            }

            guard let cam = device,
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.airdraw.video", qos: .userInitiated))

            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.captureSession.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Передаём оригинальный буфер в Vision (без зеркалирования)
        onFrame?(sampleBuffer)

        // Создаём зеркальное изображение для UI
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Зеркалируем по горизонтали для отображения как в зеркале
        ciImage = ciImage.oriented(.upMirrored)

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async { [weak self] in
                self?.currentFrame = nsImage
            }
        }
    }
}
