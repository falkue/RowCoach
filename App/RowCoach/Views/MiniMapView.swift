import SwiftUI
import UIKit
import RowCoachKit

/// Navigator: kleine genordete Karte mit Luftbild, Strecke (hin und zurück), Start, Wende und dem Boot
/// mit Fahrtrichtung. Ohne Luftbild (z. B. Teststrecke) wird nur die Linie auf dunklem Grund gezeichnet.
struct MiniMapView: View {
    let course: Course
    let pose: TrackPose
    var size: CGFloat = 200

    @Environment(CourseLibrary.self) private var library
    @State private var image: UIImage?
    @State private var track: [CGPoint] = []      // Szenenkoordinaten (x, z) der ganzen Fahrt
    @State private var turnPoint: CGPoint?

    var body: some View {
        let bounds = mapBounds
        Canvas { ctx, sz in
            func toView(_ p: CGPoint) -> CGPoint {
                CGPoint(x: (p.x - bounds.minX) / bounds.width * sz.width,
                        y: (p.y - bounds.minY) / bounds.height * sz.height)
            }
            if let image {
                ctx.draw(Image(uiImage: image), in: CGRect(origin: .zero, size: sz))
            }
            // Strecke
            if track.count > 1 {
                var path = Path()
                path.move(to: toView(track[0]))
                for p in track.dropFirst() { path.addLine(to: toView(p)) }
                ctx.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 5)
                ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 2.5)
            }
            // Start und Wende
            if let start = track.first {
                let s = toView(start)
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10)), with: .color(.green))
            }
            if let t = turnPoint {
                let v = toView(t)
                ctx.fill(Path(ellipseIn: CGRect(x: v.x - 5, y: v.y - 5, width: 10, height: 10)), with: .color(.orange))
            }
            // Boot: Dreieck in Fahrtrichtung. heading 0 = Norden (oben); Drehung im Bild um −heading.
            let b = toView(CGPoint(x: pose.x, y: pose.z))
            var tri = Path()
            tri.move(to: CGPoint(x: 0, y: -10))
            tri.addLine(to: CGPoint(x: 6.5, y: 7))
            tri.addLine(to: CGPoint(x: 0, y: 3.5))
            tri.addLine(to: CGPoint(x: -6.5, y: 7))
            tri.closeSubpath()
            let t = CGAffineTransform(translationX: b.x, y: b.y).rotated(by: -pose.heading)
            let boat = tri.applying(t)
            ctx.fill(boat, with: .color(Theme.accent))
            ctx.stroke(boat, with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topLeading) {
            Text("N").font(.caption2.bold()).foregroundStyle(.white.opacity(0.8)).padding(6)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)))
        .task(id: course.id) { prepare() }
        .accessibilityLabel("Navigator: \(Int(pose.progress * 100)) Prozent der Strecke")
    }

    /// Ausschnitt in Szenenkoordinaten: aus dem Kartenpaket, sonst quadratisch um die Strecke
    private var mapBounds: CGRect {
        if let b = course.minimap?.boundsXZ, b.count == 4 {
            return CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1])
        }
        let xs = track.map(\.x), zs = track.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let z0 = zs.min(), let z1 = zs.max() else {
            return CGRect(x: -100, y: -100, width: 200, height: 200)
        }
        let side = max(x1 - x0, z1 - z0) + 120
        return CGRect(x: (x0 + x1) / 2 - side / 2, y: (z0 + z1) / 2 - side / 2, width: side, height: side)
    }

    private func prepare() {
        let ct = CourseTrack(course: course)
        let total = ct.totalLength
        let n = max(Int(total / 10), 2)
        track = (0...n).map { i in
            let p = ct.position(atDistance: total * Double(i) / Double(n))
            return CGPoint(x: p.x, y: p.z)
        }
        if course.turns > 0 {
            let t = ct.position(atDistance: ct.oneWayLength)
            turnPoint = CGPoint(x: t.x, y: t.z)
        } else {
            turnPoint = nil
        }
        if let url = library.minimapImageURL(for: course) {
            image = UIImage(contentsOfFile: url.path)
        } else {
            image = nil
        }
    }
}

/// Streckenvorschau für die Auswahl: die Strecke von oben im Stil des Navigators (Luftbild, Linie hin und
/// zurück, Start grün, Wende orange, Fahrtrichtung am Start). Füllt die verfügbare Fläche; der Ausschnitt
/// wird so gewählt, dass die ganze Strecke mit Rand hineinpasst.
struct CourseMapPreview: View {
    let course: Course

    @Environment(CourseLibrary.self) private var library
    @State private var image: UIImage?
    @State private var imageBounds: [Double] = []
    @State private var track: [CGPoint] = []
    @State private var turnPoint: CGPoint?
    @State private var startHeading: Double = 0

    var body: some View {
        Canvas { ctx, sz in
            guard track.count > 1 else { return }
            // Ausschnitt in Szenenkoordinaten: Streckenrahmen + Rand, auf das Seitenverhältnis der Kachel gebracht
            let xs = track.map(\.x), zs = track.map(\.y)
            let x0 = xs.min()!, x1 = xs.max()!, z0 = zs.min()!, z1 = zs.max()!
            let margin = max(x1 - x0, z1 - z0) * 0.12 + 40
            var w = (x1 - x0) + 2 * margin, h = (z1 - z0) + 2 * margin
            let aspect = sz.width / max(sz.height, 1)
            if w / h < aspect { w = h * aspect } else { h = w / aspect }
            let view = CGRect(x: (x0 + x1) / 2 - w / 2, y: (z0 + z1) / 2 - h / 2, width: w, height: h)
            func toView(_ p: CGPoint) -> CGPoint {
                CGPoint(x: (p.x - view.minX) / view.width * sz.width, y: (p.y - view.minY) / view.height * sz.height)
            }
            if let image, imageBounds.count == 4 {
                let b = imageBounds
                let tl = toView(CGPoint(x: b[0], y: b[1])), br = toView(CGPoint(x: b[2], y: b[3]))
                ctx.draw(Image(uiImage: image), in: CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y))
            }
            var path = Path()
            path.move(to: toView(track[0]))
            for p in track.dropFirst() { path.addLine(to: toView(p)) }
            ctx.stroke(path, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if let t = turnPoint {
                let v = toView(t)
                ctx.fill(Path(ellipseIn: CGRect(x: v.x - 7, y: v.y - 7, width: 14, height: 14)), with: .color(.orange))
            }
            // Start mit Pfeil in Fahrtrichtung
            let s = toView(track[0])
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - 7, y: s.y - 7, width: 14, height: 14)), with: .color(.green))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: -22))
            arrow.addLine(to: CGPoint(x: 7, y: -10))
            arrow.addLine(to: CGPoint(x: -7, y: -10))
            arrow.closeSubpath()
            ctx.fill(arrow.applying(CGAffineTransform(translationX: s.x, y: s.y).rotated(by: -startHeading)), with: .color(.green))
        }
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.30), Color(red: 0.04, green: 0.09, blue: 0.13)],
                                   startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .topLeading) {
            Text("N").font(.caption2.bold()).foregroundStyle(.white.opacity(0.8)).padding(6)
        }
        .task(id: course.id) { prepare() }
    }

    private func prepare() {
        let ct = CourseTrack(course: course)
        let total = ct.totalLength
        let n = max(Int(total / 10), 2)
        track = (0...n).map { i in
            let p = ct.position(atDistance: total * Double(i) / Double(n))
            return CGPoint(x: p.x, y: p.z)
        }
        startHeading = ct.pose(atDistance: 0).heading
        if course.turns > 0 {
            let t = ct.position(atDistance: ct.oneWayLength)
            turnPoint = CGPoint(x: t.x, y: t.z)
        } else {
            turnPoint = nil
        }
        if let o = library.overviewImage(for: course) {
            image = UIImage(contentsOfFile: o.url.path)
            imageBounds = o.bounds
        } else {
            image = nil
            imageBounds = []
        }
    }
}
