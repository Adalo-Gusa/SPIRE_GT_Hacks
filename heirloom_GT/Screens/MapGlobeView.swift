import SwiftUI
import MapKit

/// A place tied to a family story, shown as a pin on the globe.
struct FamilyPlace: Identifiable {
    let id = UUID()
    var name: String
    var detail: String
    var coordinate: CLLocationCoordinate2D
    var pinColor: Color = HeirloomColor.rose
}

extension FamilyPlace {
    static let samples: [FamilyPlace] = [
        FamilyPlace(
            name: "Halifax, Nova Scotia",
            detail: "Joseph's first shortwave contact, 1962",
            coordinate: CLLocationCoordinate2D(latitude: 44.6488, longitude: -63.5752)),
        FamilyPlace(
            name: "Atlanta, Georgia",
            detail: "Where the family moved in 1978",
            coordinate: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)),
        FamilyPlace(
            name: "Durham, North Carolina",
            detail: "Grandma's first classroom",
            coordinate: CLLocationCoordinate2D(latitude: 35.9940, longitude: -78.8986),
            pinColor: HeirloomColor.plumMuted),
        FamilyPlace(
            name: "Cork, Ireland",
            detail: "The Clarke family farm",
            coordinate: CLLocationCoordinate2D(latitude: 51.8985, longitude: -8.4756)),
    ]
}

/// Apple Maps' 3D globe, drained of color and tinted into the HeirLoom tans, with pushpins for family places.
/// Spinning, pinching, tilting and rotating are all Apple Maps' own gestures.
struct MapGlobeView: View {
    var places: [FamilyPlace] = FamilyPlace.samples
    /// Multiplied over the lightened grayscale map: white becomes this color and darker grays become deeper tans.
    var tint: Color = HeirloomColor.polaroidFrame

    @State private var position: MapCameraPosition = .camera(Self.globeCamera)
    /// Latest camera, updated continuously so the pins re-project while the globe moves.
    @State private var camera: MapCamera = Self.globeCamera
    @State private var selectedID: FamilyPlace.ID?

    private static let globeCamera = MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 38, longitude: -45),
        distance: 28_000_000)

    private var selectedPlace: FamilyPlace? {
        places.first { $0.id == selectedID }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position)
                // Satellite-based styles render as a 3D globe when zoomed out (standard style stays flat in the
                // simulator); hybrid keeps country and ocean labels for orientation.
                .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
                // Grayscale, lift the shadows so oceans and space read as warm browns instead of black, then tint.
                .saturation(0)
                .brightness(0.22)
                .contrast(0.85)
                .colorMultiply(tint)
                .onMapCameraChange(frequency: .continuous) { context in
                    camera = context.camera
                }
                // Pins are drawn over the map rather than as map annotations so the tint doesn't wash them out.
                .overlay {
                    pins(using: proxy)
                }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            globeButton
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let place = selectedPlace {
                placeCard(for: place)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedID)
    }

    // MARK: - Pins

    private func pins(using proxy: MapProxy) -> some View {
        ZStack {
            ForEach(places) { place in
                if isFacingCamera(place.coordinate), let point = proxy.convert(place.coordinate, to: .local) {
                    Button {
                        select(place)
                    } label: {
                        Pushpin(color: place.pinColor, showsHole: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(place.name)
                    .pinned(at: point, tilt: .degrees(-12), scale: selectedID == place.id ? 0.75 : 0.55)
                }
            }
        }
    }

    /// Whether a coordinate is on the side of the globe facing the camera (so pins don't show through the Earth).
    private func isFacingCamera(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let earthRadius = 6_371_000.0
        let center = camera.centerCoordinate
        let lat1 = center.latitude * .pi / 180, lat2 = coordinate.latitude * .pi / 180
        let deltaLon = (coordinate.longitude - center.longitude) * .pi / 180
        let cosAngle = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(deltaLon)
        // The horizon seen from `distance` above the surface.
        return cosAngle > earthRadius / (earthRadius + camera.distance)
    }

    // MARK: - Controls

    private var globeButton: some View {
        Button {
            selectedID = nil
            withAnimation(.easeInOut(duration: 1.2)) {
                position = .camera(Self.globeCamera)
            }
        } label: {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HeirloomColor.plum)
                .frame(width: 52, height: 52)
                .glassBackground(in: Circle(), tint: HeirloomColor.plum.opacity(0.12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show whole globe")
    }

    private func placeCard(for place: FamilyPlace) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(place.pinColor)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.heirloomDisplay(18, relativeTo: .headline))
                    .foregroundStyle(HeirloomColor.plum)
                Text(place.detail)
                    .font(.subheadline)
                    .foregroundStyle(HeirloomColor.tabLabel)
            }
            Spacer(minLength: 0)
            Button {
                selectedID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HeirloomColor.tabLabel)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous), tint: HeirloomColor.plum.opacity(0.12))
    }

    private func select(_ place: FamilyPlace) {
        selectedID = place.id
        withAnimation(.easeInOut(duration: 1.4)) {
            position = .camera(MapCamera(centerCoordinate: place.coordinate, distance: 600_000))
        }
    }
}

#Preview {
    MapGlobeView()
}
