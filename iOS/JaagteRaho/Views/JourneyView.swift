import SwiftUI
import MapKit
import UIKit

struct JourneyView: View {
    @ObservedObject var journey: JourneyService
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Journey?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Every mile.\nYour story.").font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1)
                    Text("Follow your recorded route and let someone know where you are.")
                        .font(.subheadline).foregroundStyle(RahoTheme.muted)
                    RahoCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Record my journey", isOn: $journey.enabled).tint(RahoTheme.mint)
                            Text("Records GPS while a live monitoring session is open. Backgrounding pauses recording; gaps are shown in the route.")
                                .font(.caption).foregroundStyle(RahoTheme.muted)
                            StatusPill(title: journey.status, symbol: "location.fill", color: RahoTheme.amber)
                            if let current = journey.current { JourneyStats(journey: current) }
                        }
                    }
                    if let current = journey.current, !current.points.isEmpty {
                        JourneyMap(points: current.points).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    RahoCard(accent: RahoTheme.mint.opacity(0.3)) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Let them know where you are", systemImage: "location.circle.fill").font(.headline)
                            Button { journey.requestSnapshot() } label: { Label("Refresh my location", systemImage: "arrow.clockwise") }
                                .buttonStyle(RahoSecondaryButton())
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                if let point = journey.latest, point.isFresh(at: context.date) {
                                    Text("Updated \(point.timestamp.formatted(date: .omitted, time: .standard)) · ±\(Int(point.accuracy)) m")
                                        .font(.caption).foregroundStyle(RahoTheme.muted)
                                    ShareLink(item: point.shareText) { Label("Share my location", systemImage: "square.and.arrow.up") }
                                        .buttonStyle(RahoPrimaryButton())
                                } else {
                                    Text("Refresh your GPS location to share a fresh, timestamped Maps link.")
                                        .font(.caption).foregroundStyle(RahoTheme.muted)
                                }
                            }
                            Text("Choose the recipient in the share sheet. This shares a snapshot; it doesn't give anyone continuous access.")
                                .font(.caption).foregroundStyle(RahoTheme.muted)
                        }
                    }
                    if let error = journey.errorMessage { NoticeView(message: error, color: RahoTheme.red) }
                    SectionLabel(title: "Saved journeys")
                    if journey.journeys.isEmpty {
                        RahoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title).foregroundStyle(RahoTheme.mint)
                                Text("Your next journey begins here.").font(.headline)
                                Text("Enable recording, then start a live monitoring session. Synthetic demos don't record a real route.")
                                    .font(.subheadline).foregroundStyle(RahoTheme.muted)
                            }
                        }
                    }
                    ForEach(journey.journeys) { route in
                        Button { selected = route } label: {
                            RahoCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label(route.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "map.fill").font(.headline)
                                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(RahoTheme.muted)
                                    }
                                    JourneyStats(journey: route)
                                    if route.endedAt == nil { Text("Recording interrupted · showing the saved portion").font(.caption).foregroundStyle(RahoTheme.amber) }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Label("Location permissions", systemImage: "gearshape") }.foregroundStyle(RahoTheme.muted)
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(RahoTheme.midnight).foregroundStyle(RahoTheme.text)
            .navigationTitle("Your journey").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
        .sheet(item: $selected) { route in JourneyDetailView(route: route, service: journey) }
    }
}

private struct JourneyStats: View {
    let journey: Journey
    var body: some View {
        HStack(spacing: 16) {
            stat(journey.distanceLabel, "GPS distance")
            stat(journey.durationLabel, "Duration")
            stat("\(journey.checkIns)", "Check-ins")
            stat("\(journey.alarms)", "Alarms")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(RahoTheme.mint)
            Text(label).font(.caption2).foregroundStyle(RahoTheme.muted)
        }.accessibilityElement(children: .combine)
    }
}

private struct JourneyDetailView: View {
    let route: Journey
    @ObservedObject var service: JourneyService
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JourneyMap(points: route.points).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 24))
                    RahoCard { JourneyStats(journey: route) }
                    SectionLabel(title: "Journey timeline")
                    if let first = route.points.first { stop("Started", first) }
                    if let last = route.points.last { stop(route.endedAt == nil ? "Last saved position" : "Last recorded position", last) }
                    Text("GPS distance is an estimate of the recorded portions. Foreground or GPS gaps may omit travel.")
                        .font(.caption).foregroundStyle(RahoTheme.muted)
                    ShareLink(item: route.shareText) { Label("Share journey summary", systemImage: "square.and.arrow.up") }.buttonStyle(RahoPrimaryButton())
                    Button("Delete this journey", role: .destructive) { deleting = true }.frame(minHeight: 44)
                }.padding(24)
            }.background(RahoTheme.midnight).foregroundStyle(RahoTheme.text)
            .navigationTitle("Journey summary").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this journey from this phone?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete journey", role: .destructive) { service.delete(route); dismiss() }
            }
        }.preferredColorScheme(.dark)
    }
    private func stop(_ title: String, _ point: JourneyPoint) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.circle.fill").foregroundStyle(RahoTheme.amber)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(point.timestamp.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(RahoTheme.muted)
                Link(String(format: "%.4f, %.4f · View in Maps", point.latitude, point.longitude), destination: point.mapsURL).font(.caption)
            }
        }
    }
}

struct JourneyMap: UIViewRepresentable {
    let points: [JourneyPoint]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let signature = "\(points.count)-\(points.first?.timestamp.timeIntervalSince1970 ?? 0)-\(points.last?.timestamp.timeIntervalSince1970 ?? 0)"
        guard signature != context.coordinator.signature else { return }
        context.coordinator.signature = signature
        map.removeOverlays(map.overlays); map.removeAnnotations(map.annotations)
        for group in Dictionary(grouping: points, by: \.segment).values where group.count > 1 {
            let coordinates = group.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
        }
        guard let first = points.first, let last = points.last else { return }
        for (point, title) in [(first, "Start"), (last, "Last recorded location")] {
            let annotation = MKPointAnnotation(); annotation.title = title
            annotation.coordinate = .init(latitude: point.latitude, longitude: point.longitude)
            map.addAnnotation(annotation)
        }
        var rect = MKMapRect.null
        for point in points {
            let position = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            rect = rect.union(MKMapRect(x: position.x, y: position.y, width: 1, height: 1))
        }
        if rect.width < 100 && rect.height < 100 {
            map.setRegion(.init(center: .init(latitude: last.latitude, longitude: last.longitude), latitudinalMeters: 1200, longitudinalMeters: 1200), animated: false)
        } else { map.setVisibleMapRect(rect, edgePadding: .init(top: 45, left: 30, bottom: 45, right: 30), animated: false) }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var signature = ""
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = UIColor(red: 0.58, green: 0.88, blue: 0.765, alpha: 1)
            renderer.lineWidth = 5; return renderer
        }
    }
}
