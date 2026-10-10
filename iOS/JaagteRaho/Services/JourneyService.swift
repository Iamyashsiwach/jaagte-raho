import Foundation
import Combine
import CoreLocation

@MainActor
final class JourneyService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var enabled = UserDefaults.standard.bool(forKey: "journeyEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "journeyEnabled")
            if sessionActive { enabled ? beginRecording() : finish() }
        }
    }
    @Published private(set) var current: Journey?
    @Published private(set) var journeys: [Journey] = []
    @Published private(set) var latest: JourneyPoint?
    @Published private(set) var status = "Journey recording is off"
    @Published private(set) var errorMessage: String?
    private let manager = CLLocationManager()
    private let file: URL
    private var sessionActive = false
    private var suspended = false
    private var requestingSnapshot = false
    private var lastSavedAt = Date.distantPast

    override init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = folder.appendingPathComponent("saarthi-journeys.json")
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.activityType = .automotiveNavigation
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                journeys = try decoder.decode([Journey].self, from: Data(contentsOf: file))
            }
        } catch { errorMessage = "Saved journeys could not be loaded. Existing records were preserved." }
        status = enabled ? "Ready to record your next journey" : "Journey recording is off"
    }
    func startSession(simulated: Bool) {
        guard !simulated else { return }
        sessionActive = true; suspended = false
        if enabled { beginRecording() }
    }
    private func beginRecording() {
        guard enabled, sessionActive, !suspended else { return }
        if current == nil { current = Journey() }
        authorizeAndStart()
    }
    func requestSnapshot() {
        requestingSnapshot = true; latest = nil
        authorizeAndStart()
    }
    private func authorizeAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Allow location to record and share your journey"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard CLLocationManager.locationServicesEnabled() else { status = "Location services are disabled"; return }
            status = "Finding a fresh GPS location…"
            if current != nil && !suspended { manager.startUpdatingLocation() }
            else { manager.requestLocation() }
        default:
            status = "Location permission is off · enable it in iPhone settings"
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.current != nil || self.requestingSnapshot { self.authorizeAndStart() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date()
            for location in locations {
                let point = JourneyPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                         timestamp: location.timestamp, accuracy: location.horizontalAccuracy)
                guard point.isFresh(at: now) else { continue }
                self.latest = point; self.requestingSnapshot = false
                if !self.suspended, self.current != nil {
                    _ = self.current?.append(point, now: now)
                    self.status = "Recording · foreground GPS"
                    if now.timeIntervalSince(self.lastSavedAt) >= 15 { self.persist(); self.lastSavedAt = now }
                } else { self.status = "Location updated · ready to share" }
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.status = "GPS unavailable · try refreshing your location" }
    }
    func suspend() {
        suspended = true; requestingSnapshot = false
        manager.stopUpdatingLocation(); current?.breakRoute()
        if current != nil { status = "Recording paused · keep Saarthi open"; persist() }
    }
    func resume() {
        suspended = false
        if sessionActive && enabled { beginRecording() }
    }
    func record(checkIn: Bool = false, alarm: Bool = false) {
        if checkIn { current?.checkIns += 1 }
        if alarm { current?.alarms += 1 }
    }
    func endSession() { sessionActive = false; finish() }
    private func finish() {
        manager.stopUpdatingLocation(); requestingSnapshot = false
        guard var completed = current else { return }
        completed.endedAt = Date()
        journeys.removeAll { $0.id == completed.id }
        if !completed.points.isEmpty { journeys.insert(completed, at: 0) }
        current = nil; persist()
        status = enabled ? "Journey saved · ready for the next trip" : "Journey recording is off"
    }
    func delete(_ journey: Journey) { journeys.removeAll { $0.id == journey.id }; persist() }
    private func persist() {
        guard errorMessage == nil else { return }
        do {
            var records = journeys
            if let current, !current.points.isEmpty {
                records.removeAll { $0.id == current.id }; records.insert(current, at: 0)
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { errorMessage = "This journey could not be saved. Check available storage." }
    }
}
