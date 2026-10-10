import AVFoundation
import UIKit
import Combine
import MediaPipeTasksVision

/// Camera and ML work never run on the UI thread. Late frames are discarded.
final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published private(set) var errorMessage: String?
    @Published private(set) var running = false
    var onMetrics: ((FaceMetrics) -> Void)?
    var onInterruption: (() -> Void)?
    private let sessionQueue = DispatchQueue(label: "raho.camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "raho.camera.frames", qos: .userInitiated)
    private var landmarker: FaceLandmarker?
    private var configured = false
    private var lastInferenceAt: Double = 0
    private var nextInferenceAt: Double = 0
    private var lastTimestamp = 0
    private var observations: [NSObjectProtocol] = []
    private var interval: Double = 1 / 12
    private let stateLock = NSLock()
    private var generation = 0
    private var requestedRunning = false

    override init() {
        super.init()
        observations.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
                self?.running = false; self?.onInterruption?()
            })
        observations.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
                self?.running = self?.session.isRunning == true
            })
        observations.append(NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
                self?.running = false
                self?.errorMessage = "Camera interrupted. Park safely and restart monitoring."
                self?.onInterruption?()
            })
    }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        errorMessage = nil
        stateLock.lock(); generation += 1; requestedRunning = true
        let request = generation; stateLock.unlock()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart(request: request)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard self?.isRequested(request) == true else { return }
                    if allowed { self?.configureAndStart(request: request) }
                    else { self?.errorMessage = "Enable Camera in Settings to start monitoring." }
                }
            }
        default: errorMessage = "Enable Camera in Settings to start monitoring."
        }
    }
    func stop() {
        stateLock.lock(); generation += 1; requestedRunning = false; stateLock.unlock()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.running = false }
        }
    }
    func reduceForThermals() {
        frameQueue.async { [weak self] in
            let thermal = ProcessInfo.processInfo.thermalState
            self?.interval = thermal == .serious || thermal == .critical ? 1 / 8 : 1 / 12
        }
    }
    private func isRequested(_ request: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return requestedRunning && generation == request
    }
    private func configureAndStart(request: Int) {
        frameQueue.async { [weak self] in
            guard let self, self.isRequested(request) else { return }
            do {
                if self.landmarker == nil {
                    guard let model = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
                        throw CameraError.missingModel
                    }
                    let options = FaceLandmarkerOptions()
                    options.baseOptions.modelAssetPath = model
                    options.runningMode = .video
                    options.numFaces = 1
                    options.minFaceDetectionConfidence = 0.65
                    options.minFacePresenceConfidence = 0.65
                    options.minTrackingConfidence = 0.6
                    options.outputFaceBlendshapes = true
                    options.outputFacialTransformationMatrixes = true
                    self.landmarker = try FaceLandmarker(options: options)
                }
                self.sessionQueue.async { [weak self] in
                    guard let self, self.isRequested(request) else { return }
                    do {
                        if !self.configured { try self.configureSession(); self.configured = true }
                        if !self.session.isRunning { self.session.startRunning() }
                        DispatchQueue.main.async { self.running = self.session.isRunning && self.isRequested(request) }
                    } catch { self.report(error.localizedDescription) }
                }
            } catch { self.report("Face tracking could not start: \(error.localizedDescription)") }
        }
    }
    private func configureSession() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else { throw CameraError.noCamera }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input) else { throw CameraError.noCamera }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { throw CameraError.noCamera }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 24 && $0.maxFrameRate >= 24 }) {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now + 0.002 >= nextInferenceAt, let landmarker,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastInferenceAt = now
        nextInferenceAt = max(nextInferenceAt + interval, now + interval * 0.5)
        let timestamp = max(lastTimestamp + 1, Int(now * 1000)); lastTimestamp = timestamp
        let illumination = estimateIllumination(pixelBuffer)
        do {
            let image = try MPImage(sampleBuffer: sampleBuffer, orientation: .up)
            let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestamp)
            let elapsed = (ProcessInfo.processInfo.systemUptime - now) * 1000
            var metrics = FaceMetrics.missing(at: now)
            if let points = result.faceLandmarks.first, points.count >= 468 {
                let w = Double(CVPixelBufferGetWidth(pixelBuffer)), h = Double(CVPixelBufferGetHeight(pixelBuffer))
                let locations = points.map { CGPoint(x: Double($0.x) * w, y: Double($0.y) * h) }
                let left = eyeRatio(locations, [33, 160, 158, 133, 153, 144])
                let right = eyeRatio(locations, [362, 385, 387, 263, 373, 380])
                let blendshapes = result.faceBlendshapes.first?.categories ?? []
                let jaw = Double(blendshapes.first { $0.categoryName == "jawOpen" }?.score ?? 0)
                let width = distance(locations[33], locations[263])
                let pitch: Double
                if let transform = result.facialTransformationMatrixes.first,
                   transform.rows == 4, transform.columns == 4 {
                    // Row-major 4x4 rotation: pitch about the camera's horizontal axis.
                    pitch = atan2(Double(transform.data[9]), Double(transform.data[10])) * 180 / .pi
                } else { pitch = .nan }
                metrics = FaceMetrics(timestamp: now, leftEAR: left, rightEAR: right,
                                      jawOpen: jaw, pitch: pitch, facePresent: width > 45,
                                      illumination: illumination, inferenceMilliseconds: elapsed)
            }
            DispatchQueue.main.async { [weak self] in self?.onMetrics?(metrics) }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.onMetrics?(.missing(at: now)) }
        }
    }
    private func eyeRatio(_ p: [CGPoint], _ indices: [Int]) -> Double {
        let width = distance(p[indices[0]], p[indices[3]])
        guard width > 8 else { return .nan }
        return (distance(p[indices[1]], p[indices[5]]) + distance(p[indices[2]], p[indices[4]])) / (2 * width)
    }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
    private func estimateIllumination(_ buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        var total = 0.0
        for y in 1...8 { for x in 1...8 {
            let offset = (height * y / 10) * row + (width * x / 10) * 4
            total += (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / (3 * 255)
        } }
        return total / 64
    }
    private func report(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = text; self?.running = false }
    }
    private enum CameraError: LocalizedError {
        case missingModel, noCamera
        var errorDescription: String? {
            self == .missingModel ? "Bundled model missing. Run scripts/bootstrap.sh." : "Front camera unavailable. Use a physical iPhone."
        }
    }
}
