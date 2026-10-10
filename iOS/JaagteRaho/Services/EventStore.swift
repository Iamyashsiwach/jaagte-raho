import Foundation
import Combine

struct TripEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let trigger: FatigueTrigger
    let simulated: Bool
    var delivery: String
    init(trigger: FatigueTrigger, simulated: Bool) {
        id = UUID(); timestamp = Date(); self.trigger = trigger; self.simulated = simulated
        delivery = simulated ? "demo" : "pending"
    }
    var deliveryLabel: String {
        switch delivery {
        case "delivered": return "Fleet webhook accepted"
        case "stored": return "Saved on server · delivery pending"
        case "failed": return "Fleet delivery retrying"
        case "demo": return "Demo · local only"
        default: return "Queued on this phone"
        }
    }
}

@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [TripEvent] = []
    @Published private(set) var errorMessage: String?
    private let file: URL
    private var flushing = false
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("raho-events.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                events = try decoder.decode([TripEvent].self, from: Data(contentsOf: file))
            }
        } catch { errorMessage = "Event history could not be loaded. Existing records were preserved." }
    }
    func record(_ event: TripEvent) {
        guard errorMessage == nil else { return }
        events.insert(event, at: 0); persist()
    }
    func flush(using client: BackendClient?) async {
        guard let client, !flushing, errorMessage == nil else { return }
        flushing = true; defer { flushing = false }
        let pending = events.filter { !$0.simulated && $0.delivery != "delivered" }
        for event in pending {
            do {
                let receipt = try await (event.delivery == "pending" ? client.send(event) : client.receipt(for: event.id))
                if let current = events.firstIndex(where: { $0.id == receipt.id }) {
                    events[current].delivery = receipt.delivery; persist()
                }
            } catch BackendClient.BackendError.httpStatus(404) {
                // A reset backend must not strand the phone's durable copy forever.
                if let current = events.firstIndex(where: { $0.id == event.id }) {
                    events[current].delivery = "pending"; persist()
                }
            } catch { break }
        }
    }
    private func persist() {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(events).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { errorMessage = "An alert could not be saved. Check the phone's available storage." }
    }
}
