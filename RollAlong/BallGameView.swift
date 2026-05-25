import SwiftUI
import CoreMotion
import Combine

// ---------------------------------------------------------------------------
// BallGameView — a tilt-driven 3D marble on a flat arena.
//
// Foundation for a tilt-based game. Tap anywhere to (re)spawn the ball at
// that position. Tilt the device to roll it; the ball obeys a simple
// kinematic model (acceleration from gravity, rolling friction, elastic
// wall bounces). A small deadband (~3°) keeps the ball still on a level
// surface — extend the physics, add goals/obstacles/levels from here.
// ---------------------------------------------------------------------------
struct BallGameView: View {

    @StateObject private var motion = BallMotion()

    @State private var ball:      Ball? = nil
    private let ballRadius: CGFloat = 18
    private let tickRate              = 1.0 / 60.0
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark arena background
                Color(white: 0.08).ignoresSafeArea()

                // Soft inner border so the four walls read as a real arena
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                    .padding(8)

                // Onboarding hint
                if ball == nil {
                    VStack(spacing: 8) {
                        Text("Roll Along")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Tap anywhere to spawn the ball.\nTilt the phone to roll it around.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                }

                // The marble
                if let ball {
                    marble
                        .frame(width: ballRadius * 2, height: ballRadius * 2)
                        .position(ball.position)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                ball = Ball(position: location, velocity: .zero)
            }
            .onReceive(timer) { _ in
                tick(geoSize: geo.size)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    // Radial-gradient + drop-shadow marble that looks vaguely 3D.
    // The highlight is offset to the top-left so the ball reads as lit from
    // above. Adjust the colors here to retheme the ball.
    private var marble: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.00, green: 0.85, blue: 0.85),   // bright top-left
                        Color(red: 0.95, green: 0.20, blue: 0.20),
                        Color(red: 0.55, green: 0.05, blue: 0.05),
                        Color(red: 0.25, green: 0.02, blue: 0.02),   // dark bottom-right
                    ],
                    center: UnitPoint(x: 0.30, y: 0.30),
                    startRadius: 0,
                    endRadius: ballRadius * 1.4
                )
            )
            .overlay(
                Circle().stroke(.black.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
    }

    // MARK: - Physics

    private func tick(geoSize: CGSize) {
        guard var b = ball else { return }
        let dt: CGFloat = CGFloat(tickRate)

        // Acceleration from the gravity vector (already deadbanded by BallMotion).
        // Tune `accelScale` to make the ball feel heavier or lighter.
        let accelScale: CGFloat = 1800        // points / s² per unit gravity
        let ax = CGFloat(motion.gravity.x) * accelScale
        let ay = CGFloat(motion.gravity.y) * accelScale

        b.velocity.dx += ax * dt
        b.velocity.dy += ay * dt

        // Rolling friction — drains a tiny amount of energy each frame so the
        // ball doesn't roll forever at low tilts.
        b.velocity.dx *= 0.985
        b.velocity.dy *= 0.985

        // Static friction: if the phone is flat AND the ball is barely
        // moving, snap to zero. Otherwise damping alone would take many
        // seconds to fully stop.
        if motion.gravity == .zero && hypot(b.velocity.dx, b.velocity.dy) < 6 {
            b.velocity = .zero
        }

        // Step position
        b.position.x += b.velocity.dx * dt
        b.position.y += b.velocity.dy * dt

        // Bounce off the four walls. 0.55 elasticity feels like a billiard
        // ball on cushioned rails — bumpy enough to be playful, dampened
        // enough that the ball settles after a few bounces.
        let r = ballRadius
        if b.position.x < r {
            b.position.x = r
            b.velocity.dx = -b.velocity.dx * 0.55
        }
        if b.position.x > geoSize.width - r {
            b.position.x = geoSize.width - r
            b.velocity.dx = -b.velocity.dx * 0.55
        }
        if b.position.y < r {
            b.position.y = r
            b.velocity.dy = -b.velocity.dy * 0.55
        }
        if b.position.y > geoSize.height - r {
            b.position.y = geoSize.height - r
            b.velocity.dy = -b.velocity.dy * 0.55
        }

        ball = b
    }
}

private struct Ball {
    var position: CGPoint
    var velocity: CGVector
}

// ---------------------------------------------------------------------------
// BallMotion — thin wrapper around CMMotionManager that publishes a 2D
// gravity vector. A small deadband (~3°) keeps the ball still on a level
// surface; outside the deadband the raw gravity components are passed
// through verbatim.
// ---------------------------------------------------------------------------
@MainActor
final class BallMotion: ObservableObject {
    @Published var gravity: SIMD2<Float> = .zero

    private let manager  = CMMotionManager()
    private let queue    = OperationQueue()
    private let deadband: Float = 0.05    // ~3° tilt

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Map device-frame gravity onto screen-space: x is horizontal,
            // y is vertical (top-down to match SwiftUI coordinates).
            let gx = Float(motion.gravity.x)
            let gy = Float(-motion.gravity.y)
            let mag = sqrt(gx * gx + gy * gy)
            let result: SIMD2<Float> = (mag < self.deadband) ? .zero : SIMD2(gx, gy)
            Task { @MainActor in self.gravity = result }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
