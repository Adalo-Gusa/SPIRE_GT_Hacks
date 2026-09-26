import SwiftUI
import MapKit
import simd

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
    /// Where each pin is drawn. Recomputed in the map's camera callback, never while the view is drawing:
    /// MapKit's coordinate conversions inside `body` stall SwiftUI's updates for the overlay.
    @State private var placements: [FamilyPlace.ID: PinPlacement] = [:]
    @State private var selectedID: FamilyPlace.ID?

    private static let globeCamera = MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 38, longitude: -45),
        distance: 28_000_000)

    private var selectedPlace: FamilyPlace? {
        places.first { $0.id == selectedID }
    }

    var body: some View {
        globe
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
                    // Clear the yarn button, which rises about 44pt above the top of the tab bar.
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedID)
    }

    private var globe: some View {
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
                    placements = computePlacements(proxy: proxy, camera: context.camera)
                }
                // Pins are drawn over the map rather than as map annotations so the tint doesn't wash them out.
                .overlay {
                    pins
                }
        }
    }

    // MARK: - Pins

    private var pins: some View {
        ZStack {
            ForEach(places) { place in
                if let placement = placements[place.id] {
                    Button {
                        select(place)
                    } label: {
                        Pushpin(color: place.pinColor, showsHole: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(place.name)
                    .opacity(placement.opacity)
                    .pinned(
                        at: placement.point,
                        tilt: placement.tilt,
                        scale: (selectedID == place.id ? 0.75 : 0.55) * placement.scale,
                        anchor: Pushpin.tipAnchor)
                }
            }
        }
    }

    private func computePlacements(proxy: MapProxy, camera: MapCamera) -> [FamilyPlace.ID: PinPlacement] {
        let globe = GlobeProjection.measure(proxy: proxy, camera: camera)
        var result: [FamilyPlace.ID: PinPlacement] = [:]
        for place in places {
            result[place.id] = placement(for: place, proxy: proxy, globe: globe)
        }
        return result
    }

    private struct PinPlacement {
        var point: CGPoint
        var tilt: Angle
        var scale: CGFloat
        var opacity: Double
    }

    /// Where and how to draw a pin so it looks stuck into the globe's surface rather than floating over it.
    private func placement(for place: FamilyPlace, proxy: MapProxy, globe: GlobeProjection?) -> PinPlacement? {
        guard let globe else {
            // Couldn't read the camera; fall back to MapKit's own (flat-map) position.
            return proxy.convert(place.coordinate, to: .local).map {
                PinPlacement(point: $0, tilt: .degrees(-8), scale: 1, opacity: 1)
            }
        }
        // Hide anything on the far side of the Earth.
        guard let projected = globe.project(place.coordinate), projected.isFacingCamera else { return nil }
        let point = projected.point

        // How far toward the globe's edge the pin is: 0 at the middle of the disc, 1 on the horizon.
        let dx = point.x - globe.earthCenter.x, dy = point.y - globe.earthCenter.y
        let edge = min(hypot(dx, dy) / globe.screenRadius, 1)
        // Direction from the globe's middle, measured clockwise from straight up.
        let direction = atan2(dx, -dy)
        // Lean outward on the left and right, shrink toward the edge, and fade out at the horizon.
        return PinPlacement(
            point: point,
            tilt: .degrees(Double(sin(direction) * edge) * 55),
            scale: 1 - 0.3 * edge * edge,
            opacity: edge > 0.9 ? Double((1 - edge) / 0.1) : 1)
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

/// Projects coordinates onto the globe the way MapKit draws it.
///
/// `MapProxy.convert` doesn't know about the globe: it places points as if on the flat (Web Mercator) map,
/// which matches the globe near the middle of the screen but drifts badly toward the edges, and even puts
/// far-side places out in space. So this rebuilds MapKit's camera (a perspective camera `distance` above the
/// center coordinate, turned by `heading` and tilted by `pitch`) and projects onto a real sphere. The lens
/// scale is calibrated each frame from MapKit's own scale at the screen center, where flat and globe agree.
private struct GlobeProjection {
    struct Projected {
        var point: CGPoint
        /// Whether the place is on the side of the Earth facing the camera.
        var isFacingCamera: Bool
    }

    /// Screen position of the camera's target (MapKit keeps it at the middle of the view).
    private var viewCenter: CGPoint
    /// Lens scale in points (screen distance per unit of view-space slope).
    private var focal: Double
    /// Camera position and orientation, in Earth radii with the Earth's center at the origin.
    private var eye: SIMD3<Double>
    private var viewDirection: SIMD3<Double>
    private var screenUp: SIMD3<Double>
    private var screenRight: SIMD3<Double>

    static func measure(proxy: MapProxy, camera: MapCamera) -> GlobeProjection? {
        let target = camera.centerCoordinate
        guard let viewCenter = proxy.convert(target, to: .local) else { return nil }

        // Calibrate: a tiny north/south step near the center shows how many points one radian of arc covers.
        let step = 0.2
        let stepLatitude = target.latitude >= 0 ? target.latitude - step : target.latitude + step
        guard let stepped = proxy.convert(
            CLLocationCoordinate2D(latitude: stepLatitude, longitude: target.longitude), to: .local)
        else { return nil }
        let pointsPerRadian = Double(hypot(stepped.x - viewCenter.x, stepped.y - viewCenter.y)) / (step * .pi / 180)
        let distance = camera.distance / 6_371_000
        guard pointsPerRadian > 0, distance > 0 else { return nil }

        let up = unitVector(target)
        let lambda = target.longitude * .pi / 180, phi = target.latitude * .pi / 180
        let east = SIMD3(-sin(lambda), cos(lambda), 0)
        let north = SIMD3(-sin(phi) * cos(lambda), -sin(phi) * sin(lambda), cos(phi))
        let heading = camera.heading * .pi / 180, pitch = camera.pitch * .pi / 180
        let forward = north * cos(heading) + east * sin(heading)

        let eye = up + (up * cos(pitch) - forward * sin(pitch)) * distance
        let viewDirection = simd_normalize(up - eye)
        let screenUp = forward * cos(pitch) + up * sin(pitch)
        return GlobeProjection(
            viewCenter: viewCenter,
            focal: pointsPerRadian * distance,
            eye: eye,
            viewDirection: viewDirection,
            screenUp: screenUp,
            screenRight: simd_cross(viewDirection, screenUp))
    }

    func project(_ coordinate: CLLocationCoordinate2D) -> Projected? {
        let surface = Self.unitVector(coordinate)
        return project(surface).map { Projected(point: $0, isFacingCamera: simd_dot(surface, eye) > 1) }
    }

    /// Where the middle of the Earth lands on screen; pins lean away from it.
    var earthCenter: CGPoint { project(SIMD3(0, 0, 0)) ?? viewCenter }

    /// Radius of the globe's outline on screen.
    var screenRadius: CGFloat {
        let eyeDistance = simd_length(eye)
        guard eyeDistance > 1 else { return .greatestFiniteMagnitude }
        return CGFloat(focal * tan(asin(1 / eyeDistance)))
    }

    private func project(_ position: SIMD3<Double>) -> CGPoint? {
        let offset = position - eye
        let depth = simd_dot(offset, viewDirection)
        guard depth > 0 else { return nil }
        return CGPoint(
            x: viewCenter.x + simd_dot(offset, screenRight) / depth * focal,
            y: viewCenter.y - simd_dot(offset, screenUp) / depth * focal)
    }

    private static func unitVector(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Double> {
        let phi = coordinate.latitude * .pi / 180, lambda = coordinate.longitude * .pi / 180
        return SIMD3(cos(phi) * cos(lambda), cos(phi) * sin(lambda), sin(phi))
    }
}
