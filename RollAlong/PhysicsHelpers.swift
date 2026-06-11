import CoreGraphics

// ---------------------------------------------------------------------------
// PhysicsHelpers — pure free functions shared by multiple minigame views.
//
// All functions operate on primitive CoreGraphics types (CGPoint, CGVector,
// CGSize) so they carry no view state and are straightforward to unit-test.
//
// Extracted from:
//   • SnakeGameView  (bounceEdges, resolveWallSegment, resolveCircleObstacle)
//   • GoldRushView   (bounceEdges, resolveWallSegment)
//
// KingOfTheHillView.resolvePillarCollisions handles a whole-racer-array
// loop with a different impulse formula and is intentionally not extracted.
// ---------------------------------------------------------------------------

// MARK: - bounceEdges

/// Clamp a moving circle to arena bounds and reflect velocity on contact.
///
/// Uses the `abs` form of reflection — forces direction away from each wall
/// regardless of the incoming velocity sign, so multiple overlapping
/// collisions in one tick don't accidentally cancel each other out.
///
/// - Parameters:
///   - pos:         Ball centre position in arena pixel coordinates (mutated).
///   - vel:         Ball velocity in pixels/tick (mutated).
///   - radius:      Ball radius in pixels.
///   - arena:       Arena size in pixels.
///   - restitution: Fraction of speed retained after hitting a wall (0…1).
func bounceEdges(pos: inout CGPoint,
                 vel: inout CGVector,
                 radius: CGFloat,
                 arena: CGSize,
                 restitution: CGFloat) {
    if pos.x < radius {
        pos.x = radius
        vel.dx = abs(vel.dx) * restitution
    } else if pos.x > arena.width - radius {
        pos.x = arena.width - radius
        vel.dx = -abs(vel.dx) * restitution
    }
    if pos.y < radius {
        pos.y = radius
        vel.dy = abs(vel.dy) * restitution
    } else if pos.y > arena.height - radius {
        pos.y = arena.height - radius
        vel.dy = -abs(vel.dy) * restitution
    }
}

// MARK: - resolveWallSegment

/// Push a ball out of a line segment and reflect its velocity.
///
/// Projects the ball centre onto the segment, finds the closest point,
/// and if the distance is within `radius` pushes the ball out along
/// the contact normal and reflects the velocity component along that normal.
///
/// No-op when the ball is not overlapping the segment.
///
/// - Parameters:
///   - pos:         Ball centre in arena pixel coordinates (mutated).
///   - vel:         Ball velocity (mutated).
///   - p1, p2:      Segment endpoints in arena pixel coordinates.
///   - radius:      Ball radius in pixels.
///   - restitution: Fraction of the reflected velocity component retained (0…1).
func resolveWallSegment(pos: inout CGPoint,
                        vel: inout CGVector,
                        p1: CGPoint,
                        p2: CGPoint,
                        radius: CGFloat,
                        restitution: CGFloat) {
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    let lenSq = dx * dx + dy * dy
    guard lenSq > 0 else { return }
    let t = max(0, min(1, ((pos.x - p1.x) * dx + (pos.y - p1.y) * dy) / lenSq))
    let nx = pos.x - (p1.x + t * dx)
    let ny = pos.y - (p1.y + t * dy)
    let dist = hypot(nx, ny)
    guard dist < radius, dist > 0 else { return }
    let inv = 1 / dist
    let nnx = nx * inv, nny = ny * inv
    pos.x += nnx * (radius - dist)
    pos.y += nny * (radius - dist)
    let dot = vel.dx * nnx + vel.dy * nny
    vel.dx -= 2 * dot * nnx * restitution
    vel.dy -= 2 * dot * nny * restitution
}

// MARK: - resolveCircleObstacle

/// Push a ball out of a circular obstacle and reflect its velocity.
///
/// Only applies an impulse when the ball's velocity has a component
/// toward the obstacle (`dot < 0` guard), preventing the ball from
/// sticking when already separating.
///
/// No-op when the ball is not overlapping the obstacle.
///
/// - Parameters:
///   - pos:             Ball centre (mutated).
///   - vel:             Ball velocity (mutated).
///   - centre:          Obstacle centre in arena pixel coordinates.
///   - obstacleRadius:  Obstacle radius in pixels.
///   - ballRadius:      Ball radius in pixels.
///   - restitution:     Fraction of speed retained after reflection (0…1).
func resolveCircleObstacle(pos: inout CGPoint,
                           vel: inout CGVector,
                           centre: CGPoint,
                           obstacleRadius: CGFloat,
                           ballRadius: CGFloat,
                           restitution: CGFloat) {
    let dx = pos.x - centre.x, dy = pos.y - centre.y
    let dist = hypot(dx, dy)
    let minD = ballRadius + obstacleRadius
    guard dist < minD, dist > 0 else { return }
    let inv = 1 / dist
    let nx = dx * inv, ny = dy * inv
    pos.x += nx * (minD - dist)
    pos.y += ny * (minD - dist)
    let dot = vel.dx * nx + vel.dy * ny
    guard dot < 0 else { return }
    vel.dx -= 2 * dot * nx * restitution
    vel.dy -= 2 * dot * ny * restitution
}
