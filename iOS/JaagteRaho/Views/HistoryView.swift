import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: EventStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Every alert.\nA reason to rest.")
                            .font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-0.7)
                        Text("Critical alerts are saved on this phone. Real events stay queued until the backend can deliver them.")
                            .font(.subheadline).foregroundStyle(RahoTheme.muted).lineSpacing(3)
                    }
                    if let error = store.errorMessage { NoticeView(message: error, color: RahoTheme.red) }
                    if store.events.isEmpty {
                        RahoCard {
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(RahoTheme.mint)
                                Text("No alerts recorded yet").font(.headline)
                                Text("Completed critical alerts appear here with their time, trigger and fleet delivery status. Synthetic demo events are labeled separately.")
                                    .font(.subheadline).foregroundStyle(RahoTheme.muted)
                            }
                            .padding(.vertical, 16)
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.events) { event in AlertHistoryRow(event: event) }
                        }
                    }
                    Text("“Fleet webhook accepted” records the server's delivery result. It does not confirm that a person has read the alert.")
                        .font(.caption).foregroundStyle(RahoTheme.muted).lineSpacing(3)
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(RahoTheme.midnight)
            .foregroundStyle(RahoTheme.text)
            .navigationTitle("Alert history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AlertHistoryRow: View {
    let event: TripEvent
    private var delivered: Bool { event.delivery == "delivered" }

    var body: some View {
        RahoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: event.simulated ? "play.rectangle.fill" : "exclamationmark.triangle.fill")
                        .font(.title3).foregroundStyle(event.simulated ? RahoTheme.amber : RahoTheme.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.trigger.title).font(.headline)
                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(RahoTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                StatusPill(title: event.deliveryLabel,
                           symbol: event.simulated ? "play.fill" : (delivered ? "checkmark.circle.fill" : "clock.fill"),
                           color: delivered ? RahoTheme.mint : RahoTheme.amber)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
