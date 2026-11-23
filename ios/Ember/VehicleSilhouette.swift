import SwiftUI

// MARK: - Vehicle silhouette (side view) with working lights

/// A solid side-view silhouette in the vehicle's paint color, with
/// headlights, taillights and amber turn signals.
/// - running: headlights brighten and shine forward
/// - hazards / panic: turn signals blink (panic also flashes the lamps)
/// - alarm: red glow around the whole vehicle
struct VehicleSilhouette: View {
    var type: VehicleType
    var color: Color
    var running = false
    var hazards = false
    var panic = false
    var alarm = false

    @Environment(\.colorScheme) private var scheme

    private var animating: Bool { hazards || panic || alarm }

    var body: some View {
        TimelineView(.periodic(from: .now, by: animating ? 0.5 : 3600)) { timeline in
            let blinkOn = !animating || Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Canvas { g, size in draw(in: &g, size: size, blinkOn: blinkOn) }
        }
        .aspectRatio(VehicleOutline.width / VehicleOutline.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(in g: inout GraphicsContext, size: CGSize, blinkOn: Bool) {
        let o = VehicleOutline.of(type)
        let s = min(size.width / VehicleOutline.width, size.height / VehicleOutline.height)
        g.translateBy(x: (size.width - VehicleOutline.width * s) / 2,
                      y: (size.height - VehicleOutline.height * s) / 2 - VehicleOutline.top * s)
        g.scaleBy(x: s, y: s)

        let ground = VehicleOutline.wheelY
        let edge: Color = scheme == .dark ? .white.opacity(0.22) : .black.opacity(0.16)

        // Ground shadow
        g.fill(Path(ellipseIn: CGRect(x: o.rear - 6, y: ground + o.wheelRadius - 4,
                                      width: o.front - o.rear + 12, height: 9)),
               with: .color(.black.opacity(scheme == .dark ? 0.45 : 0.18)))

        // Alarm: red glow around the body
        if alarm {
            g.drawLayer { layer in
                layer.opacity = blinkOn ? 1 : 0.4
                layer.addFilter(.blur(radius: 5))
                layer.stroke(o.body, with: .color(.red), lineWidth: 7)
            }
        }

        // Headlight beam while the engine runs
        if running {
            var beam = Path()
            beam.move(to: CGPoint(x: o.front - 1, y: o.headY))
            beam.addLine(to: CGPoint(x: o.front + 46, y: o.headY - 11))
            beam.addLine(to: CGPoint(x: o.front + 46, y: o.headY + 17))
            beam.addLine(to: CGPoint(x: o.front - 1, y: o.headY + 5))
            beam.closeSubpath()
            g.fill(beam, with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                               startPoint: CGPoint(x: o.front, y: 0),
                                               endPoint: CGPoint(x: o.front + 46, y: 0)))
        }

        // Body, roof rails and mirror
        g.fill(o.body, with: .color(color))
        if let rails = o.rails {
            g.stroke(rails, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
        g.fill(o.mirror, with: .color(color))
        let bounds = o.body.boundingRect
        g.fill(o.body, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.28), location: 0),
                             .init(color: .white.opacity(0), location: 0.35)]),
            startPoint: CGPoint(x: 0, y: bounds.minY), endPoint: CGPoint(x: 0, y: bounds.maxY)))
        g.stroke(o.body, with: .color(edge), lineWidth: 0.9)

        // Wheels: solid, a shade darker than the body
        for cx in o.wheels {
            let wheel = Path(ellipseIn: CGRect(x: cx - o.wheelRadius, y: ground - o.wheelRadius,
                                               width: o.wheelRadius * 2, height: o.wheelRadius * 2))
            g.fill(wheel, with: .color(color))
            g.fill(wheel, with: .color(.black.opacity(0.28)))
            g.stroke(wheel, with: .color(edge), lineWidth: 0.9)
        }

        // Headlights and taillights, with a soft glow
        let lampLevel: Double = panic ? (blinkOn ? 1 : 0.2) : (running ? 1 : 0.7)
        glow(&g, o.head, .white, opacity: lampLevel, radius: running ? 4 : 2.5)
        glow(&g, o.tail, Color(red: 1, green: 0.16, blue: 0.16), opacity: panic ? lampLevel : 1, radius: 2.5)

        // Amber turn signals
        if (hazards || panic) && blinkOn {
            let amber = Color(red: 1, green: 0.66, blue: 0.18)
            for p in o.signals {
                let w: CGFloat = p.x < 50 ? 6 : 11
                let rect = Path(roundedRect: CGRect(x: p.x, y: p.y, width: w, height: 3), cornerRadius: 1.5)
                g.drawLayer { layer in
                    layer.addFilter(.blur(radius: 5))
                    layer.fill(Path(ellipseIn: CGRect(x: p.x + w / 2 - 12, y: p.y - 5.5, width: 24, height: 14)),
                               with: .color(amber.opacity(0.8)))
                }
                glow(&g, rect, amber, opacity: 1, radius: 2)
            }
        }

        // Horn waves during panic
        if panic && blinkOn {
            var waves = Path()
            for (dx, r) in [(CGFloat(7), CGFloat(8)), (CGFloat(14), CGFloat(15))] {
                waves.move(to: CGPoint(x: o.front + dx, y: o.headY - r + 2))
                waves.addQuadCurve(to: CGPoint(x: o.front + dx, y: o.headY + r + 2),
                                   control: CGPoint(x: o.front + dx + r * 0.9, y: o.headY + 2))
            }
            g.stroke(waves, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func glow(_ g: inout GraphicsContext, _ path: Path, _ color: Color, opacity: Double, radius: CGFloat) {
        g.drawLayer { layer in
            layer.opacity = opacity
            layer.addFilter(.blur(radius: radius))
            layer.fill(path, with: .color(color))
            layer.fill(path, with: .color(color))
        }
        g.drawLayer { layer in
            layer.opacity = opacity
            layer.fill(path, with: .color(color))
        }
    }
}

// MARK: - Shapes

/// Silhouette outlines on a 250 x 98 grid (front of the vehicle on the right).
struct VehicleOutline {
    static let width: CGFloat = 250
    static let height: CGFloat = 98
    static let top: CGFloat = 4
    static let wheelY: CGFloat = 78

    let wheels: [CGFloat]
    let wheelRadius: CGFloat
    let front: CGFloat
    let rear: CGFloat
    let headY: CGFloat
    let body: Path
    let head: Path
    let tail: Path
    let mirror: Path
    let rails: Path?
    let signals: [CGPoint]

    init(wheels: [CGFloat], wheelRadius: CGFloat, front: CGFloat, rear: CGFloat, headY: CGFloat,
         body: String, head: String, tail: String, mirror: CGPoint, rails: String? = nil, signals: [CGPoint]) {
        self.wheels = wheels
        self.wheelRadius = wheelRadius
        self.front = front
        self.rear = rear
        self.headY = headY
        self.body = SVGPath.parse(body)
        self.head = SVGPath.parse(head)
        self.tail = SVGPath.parse(tail)
        var m = Path()
        m.move(to: mirror)
        m.addLine(to: CGPoint(x: mirror.x + 6, y: mirror.y - 4))
        m.addLine(to: CGPoint(x: mirror.x + 10, y: mirror.y - 4))
        m.addLine(to: CGPoint(x: mirror.x + 9, y: mirror.y + 1))
        m.closeSubpath()
        self.mirror = m
        self.rails = rails.map(SVGPath.parse)
        self.signals = signals
    }

    static func of(_ type: VehicleType) -> VehicleOutline {
        switch type {
        case .car: return car
        case .hatchback: return hatchback
        case .suv: return suv
        case .truck: return truck
        }
    }

    static let car = VehicleOutline(
        wheels: [55, 193], wheelRadius: 16, front: 236, rear: 10, headY: 55,
        body: "M10 74L10 57C10 51 13 48 19 47.5L48 45.5C60 37 74 31.5 92 29.5C108 28 126 28 140 29.5C153 31.5 165 38 179 46L222 50C231 51 236 56 236 63L236 74C236 77 234 78 231 78L213 78A20 20 0 0 0 173 78L75 78A20 20 0 0 0 35 78L13 78C11 78 10 77 10 74Z",
        head: "M222 52L235 56L235.5 60L220 57.5Z", tail: "M10.5 50.5L22 49L22 53.5L10 55.5Z",
        mirror: CGPoint(x: 166, y: 44), signals: [CGPoint(x: 222, y: 62), CGPoint(x: 11, y: 58)])

    static let hatchback = VehicleOutline(
        wheels: [52, 186], wheelRadius: 15.5, front: 222, rear: 14, headY: 53,
        body: "M14 74L14 58C14 53 15 50 18 47C24 40 32 33.5 44 30C62 25.5 92 24.5 116 26C136 27.5 152 34.5 168 44.5L208 49C216 50 222 54 222 61L222 74C222 77 220 78 217 78L205 78A19 19 0 0 0 167 78L71 78A19 19 0 0 0 33 78L17 78C15 78 14 77 14 74Z",
        head: "M208 50.5L221 55L221.5 59L206 56Z", tail: "M15.5 48L24 41L25 47L15 52Z",
        mirror: CGPoint(x: 154, y: 43), signals: [CGPoint(x: 208, y: 61), CGPoint(x: 15, y: 54)])

    static let suv = VehicleOutline(
        wheels: [53, 193], wheelRadius: 17, front: 234, rear: 12, headY: 49,
        body: "M12 74L12 46C12 38 14 32 18 26L22 20C24 17 27 16 32 16L150 16C160 16 168 22 178 34L188 42L218 46C228 48 234 55 234 64L234 74C234 77 232 78 228 78L214 78A21 21 0 0 0 172 78L74 78A21 21 0 0 0 32 78L16 78C13 78 12 77 12 74Z",
        head: "M219 46L233 51L233.5 56L217 52Z", tail: "M13 30L19 29L19 46L12.5 47Z",
        mirror: CGPoint(x: 176, y: 36), rails: "M30 13.5H150",
        signals: [CGPoint(x: 220, y: 57), CGPoint(x: 13, y: 49)])

    static let truck = VehicleOutline(
        wheels: [55, 193], wheelRadius: 18.5, front: 234, rear: 8, headY: 45,
        body: "M8 74L8 40C8 38 9 37 11 37L104 37L106 18C107 14 110 12 114 12L150 12C157 12 161 15 165 20L178 36L220 40C228 41 234 47 234 56L234 74C234 77 232 78 229 78L216 78A23 23 0 0 0 170 78L78 78A23 23 0 0 0 32 78L11 78C9 78 8 77 8 74Z",
        head: "M221 42L233 47L233.5 52L219 48Z", tail: "M8 41H14V56H8Z",
        mirror: CGPoint(x: 166, y: 32), signals: [CGPoint(x: 222, y: 53), CGPoint(x: 8, y: 58)])
}

// MARK: - Minimal SVG path reader (M L H V C A Z, absolute)

enum SVGPath {
    static func parse(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func number() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        func point() -> CGPoint {
            let x = number()
            let y = number()
            return CGPoint(x: x, y: y)
        }

        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                command = c
                i += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = start
                    continue
                }
            }
            switch command {
            case "M":
                current = point()
                path.move(to: current)
                start = current
                command = "L"
            case "L":
                current = point()
                path.addLine(to: current)
            case "H":
                current.x = number()
                path.addLine(to: current)
            case "V":
                current.y = number()
                path.addLine(to: current)
            case "C":
                let c1 = point(), c2 = point(), end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "A":
                // Only used for wheel arches: a half circle over the top between two points.
                for _ in 0..<5 { _ = number() }
                let end = point()
                let cx = (current.x + end.x) / 2
                let r = abs(end.x - current.x) / 2
                let k: CGFloat = 0.5523
                let dir: CGFloat = end.x < current.x ? 1 : -1
                let peak = CGPoint(x: cx, y: current.y - r)
                path.addCurve(to: peak,
                              control1: CGPoint(x: current.x, y: current.y - k * r),
                              control2: CGPoint(x: cx + dir * k * r, y: peak.y))
                path.addCurve(to: end,
                              control1: CGPoint(x: cx - dir * k * r, y: peak.y),
                              control2: CGPoint(x: end.x, y: end.y - k * r))
                current = end
            default:
                i += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number); number = "" }
        }
        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(String(ch))
            } else if ch == "-" {
                flush()
                number = "-"
            } else if ch == "." {
                if number.contains(".") { flush() }
                number.append(ch)
            } else if ch.isNumber {
                number.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(VehicleType.allCases) { t in
            VehicleSilhouette(type: t, color: .red, running: t == .car, hazards: t == .suv)
                .frame(height: 90)
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
