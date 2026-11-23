import SwiftUI

/// Slowly drifting "night drive" backdrop: deep indigo sky with a warm ember glow
/// rising from below. The glow brightens and warms up while the engine runs.
/// Gives the Liquid Glass cards something colorful to refract.
struct EmberBackground: View {
    var running: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var light: Bool { scheme == .light }

    var body: some View {
        ZStack {
            if #available(iOS 18.0, *) {
                // The drift is slow, so 15 frames a second looks identical to 30 and
                // halves the work. It holds still in Low Power Mode or with Reduce Motion.
                TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || lowPower)) { context in
                    mesh(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                fallback
            }
            // Soft vignette keeps text readable at the edges.
            RadialGradient(colors: [.clear, .black.opacity(light ? 0.06 : 0.55)],
                           center: .center, startRadius: 180, endRadius: 650)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: running)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: iOS 18+: animated mesh gradient

    @available(iOS 18.0, *)
    private func mesh(time t: Double) -> some View {
        let s = Float(t)
        // 3x3 grid; the middle points wander slowly.
        let leftY: Float = 0.5 + 0.06 * sin(s * 0.35)
        let midX: Float = 0.5 + 0.12 * sin(s * 0.27)
        let midY: Float = 0.55 + 0.08 * cos(s * 0.31)
        let rightY: Float = 0.5 + 0.06 * cos(s * 0.29)
        let bottomX: Float = 0.5 + 0.10 * sin(s * 0.23)
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, leftY), SIMD2(midX, midY), SIMD2(1, rightY),
            SIMD2(0, 1), SIMD2(bottomX, 1), SIMD2(1, 1),
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }

    private var colors: [Color] {
        if light {
            let mist = Color(red: 0.95, green: 0.95, blue: 0.97)
            let lilac = Color(red: 0.90, green: 0.89, blue: 0.97)
            let blush = Color(red: 0.98, green: 0.90, blue: 0.90)
            let sky = Color(red: 0.88, green: 0.93, blue: 0.98)
            let peach = running ? Color(red: 1.00, green: 0.76, blue: 0.62) : Color(red: 0.99, green: 0.86, blue: 0.78)
            let sand = running ? Color(red: 0.99, green: 0.84, blue: 0.76) : Color(red: 0.97, green: 0.92, blue: 0.89)
            return [
                mist, lilac, mist,
                sky,  blush, lilac,
                sand, peach, sand,
            ]
        }
        let night = Color(red: 0.04, green: 0.04, blue: 0.10)
        let indigo = Color(red: 0.10, green: 0.08, blue: 0.24)
        let plum = Color(red: 0.24, green: 0.08, blue: 0.22)
        let ember = running ? Color(red: 1.00, green: 0.40, blue: 0.16) : Color(red: 0.72, green: 0.26, blue: 0.12)
        let coal = running ? Color(red: 0.55, green: 0.12, blue: 0.08) : Color(red: 0.28, green: 0.08, blue: 0.10)
        let teal = Color(red: 0.05, green: 0.20, blue: 0.30)
        return [
            night,  indigo, night,
            teal,   plum,   indigo,
            coal,   ember,  coal,
        ]
    }

    // MARK: iOS 17: static layered gradient

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: light
                           ? [Color(red: 0.95, green: 0.95, blue: 0.97), Color(red: 0.90, green: 0.89, blue: 0.97)]
                           : [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.10, green: 0.08, blue: 0.24)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(running ? Color(red: 1.0, green: 0.40, blue: 0.16) : Color(red: 0.72, green: 0.26, blue: 0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 140)
                .offset(y: 380)
            Circle()
                .fill(Color(red: 0.05, green: 0.25, blue: 0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 120)
                .offset(x: -160, y: -60)
        }
    }
}
