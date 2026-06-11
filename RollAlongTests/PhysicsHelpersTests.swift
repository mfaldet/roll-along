import XCTest
@testable import RollAlong

final class PhysicsHelpersTests: XCTestCase {

    // MARK: - bounceEdges

    func testBounceEdges_ballAtLeftEdge_clampsAndReflects() {
        var pos = CGPoint(x: -3, y: 100)
        var vel = CGVector(dx: -5, dy: 0)
        let arena = CGSize(width: 400, height: 800)
        bounceEdges(pos: &pos, vel: &vel, radius: 10, arena: arena, restitution: 0.8)
        XCTAssertGreaterThanOrEqual(pos.x, 10, "Ball should be clamped to at least radius from left edge")
        XCTAssertGreaterThan(vel.dx, 0, "Velocity x should be reflected to positive")
    }

    func testBounceEdges_ballAtRightEdge_clampsAndReflects() {
        var pos = CGPoint(x: 395, y: 100)
        var vel = CGVector(dx: 5, dy: 0)
        let arena = CGSize(width: 400, height: 800)
        bounceEdges(pos: &pos, vel: &vel, radius: 10, arena: arena, restitution: 0.8)
        XCTAssertLessThanOrEqual(pos.x, 390, "Ball should be clamped to at most width - radius")
        XCTAssertLessThan(vel.dx, 0, "Velocity x should be reflected to negative")
    }

    func testBounceEdges_ballAtTopEdge_clampsAndReflects() {
        var pos = CGPoint(x: 200, y: -2)
        var vel = CGVector(dx: 0, dy: -4)
        let arena = CGSize(width: 400, height: 800)
        bounceEdges(pos: &pos, vel: &vel, radius: 10, arena: arena, restitution: 1.0)
        XCTAssertGreaterThanOrEqual(pos.y, 10)
        XCTAssertGreaterThan(vel.dy, 0)
    }

    func testBounceEdges_ballAtBottomEdge_clampsAndReflects() {
        var pos = CGPoint(x: 200, y: 795)
        var vel = CGVector(dx: 0, dy: 3)
        let arena = CGSize(width: 400, height: 800)
        bounceEdges(pos: &pos, vel: &vel, radius: 10, arena: arena, restitution: 1.0)
        XCTAssertLessThanOrEqual(pos.y, 790)
        XCTAssertLessThan(vel.dy, 0)
    }

    func testBounceEdges_ballInsideArena_noChange() {
        var pos = CGPoint(x: 200, y: 400)
        var vel = CGVector(dx: 3, dy: -2)
        let arena = CGSize(width: 400, height: 800)
        let beforePos = pos, beforeVel = vel
        bounceEdges(pos: &pos, vel: &vel, radius: 10, arena: arena, restitution: 0.8)
        XCTAssertEqual(pos.x, beforePos.x)
        XCTAssertEqual(pos.y, beforePos.y)
        XCTAssertEqual(vel.dx, beforeVel.dx)
        XCTAssertEqual(vel.dy, beforeVel.dy)
    }

    func testBounceEdges_restitutionScalesSpeed() {
        var pos = CGPoint(x: -1, y: 200)
        var vel = CGVector(dx: -10, dy: 0)
        let arena = CGSize(width: 400, height: 800)
        bounceEdges(pos: &pos, vel: &vel, radius: 10, arena: arena, restitution: 0.5)
        XCTAssertEqual(vel.dx, 5.0, accuracy: 0.001,
                       "Reflected speed should be |incoming| * restitution = 10 * 0.5 = 5")
    }

    // MARK: - resolveWallSegment

    func testResolveWallSegment_ballOverlappingHorizontalWall_pushesOutAndReflects() {
        // Horizontal wall from (80, 400) to (320, 400); ball centre 4 px below
        let p1 = CGPoint(x: 80, y: 400), p2 = CGPoint(x: 320, y: 400)
        var pos = CGPoint(x: 200, y: 396)   // 4 px below wall, inside radius=10
        var vel = CGVector(dx: 0, dy: -3)    // moving toward wall (upward)
        resolveWallSegment(pos: &pos, vel: &vel, p1: p1, p2: p2, radius: 10, restitution: 0.9)
        // Ball should be pushed below the wall by at least the radius
        XCTAssertLessThanOrEqual(pos.y, 400 - 10 + 0.01,
                                 "Ball centre should be at least radius below wall")
        // Vertical velocity should now point downward (reflected away from wall)
        XCTAssertGreaterThan(vel.dy, 0, "Velocity y should be reflected downward")
    }

    func testResolveWallSegment_ballFarFromSegment_noChange() {
        let p1 = CGPoint(x: 0, y: 0), p2 = CGPoint(x: 400, y: 0)  // top edge wall
        var pos = CGPoint(x: 200, y: 400)  // far from wall
        var vel = CGVector(dx: 1, dy: 1)
        let beforePos = pos, beforeVel = vel
        resolveWallSegment(pos: &pos, vel: &vel, p1: p1, p2: p2, radius: 10, restitution: 0.9)
        XCTAssertEqual(pos.x, beforePos.x)
        XCTAssertEqual(pos.y, beforePos.y)
        XCTAssertEqual(vel.dx, beforeVel.dx)
        XCTAssertEqual(vel.dy, beforeVel.dy)
    }

    func testResolveWallSegment_ballBeyondEndpoint_usesClosestEndpoint() {
        // Vertical wall from (200, 100) to (200, 300); ball is below the segment
        let p1 = CGPoint(x: 200, y: 100), p2 = CGPoint(x: 200, y: 300)
        var pos = CGPoint(x: 205, y: 400)  // past p2, close to x=200 but y=400
        var vel = CGVector(dx: -2, dy: 0)
        let beforePos = pos, beforeVel = vel
        resolveWallSegment(pos: &pos, vel: &vel, p1: p1, p2: p2, radius: 10, restitution: 0.9)
        // Distance from (205, 400) to closest endpoint (200, 300) = hypot(5, 100) >> 10
        // → no collision
        XCTAssertEqual(pos.x, beforePos.x)
        XCTAssertEqual(pos.y, beforePos.y)
        XCTAssertEqual(vel.dx, beforeVel.dx)
        XCTAssertEqual(vel.dy, beforeVel.dy)
    }

    func testResolveWallSegment_zeroLengthSegment_isNoOp() {
        let p1 = CGPoint(x: 200, y: 200), p2 = CGPoint(x: 200, y: 200)
        var pos = CGPoint(x: 200, y: 200)
        var vel = CGVector(dx: 1, dy: 0)
        let beforeVel = vel
        resolveWallSegment(pos: &pos, vel: &vel, p1: p1, p2: p2, radius: 10, restitution: 0.9)
        XCTAssertEqual(vel.dx, beforeVel.dx)
        XCTAssertEqual(vel.dy, beforeVel.dy)
    }

    // MARK: - resolveCircleObstacle

    func testResolveCircleObstacle_overlappingBall_pushesOutToMinDistance() {
        // Obstacle at (200, 400), radius 15; ball centre at (205, 400), radius 10
        // Combined radii = 25; current distance = 5 → overlap of 20 px
        var pos = CGPoint(x: 205, y: 400)
        var vel = CGVector(dx: -2, dy: 0)    // moving toward obstacle
        let centre = CGPoint(x: 200, y: 400)
        resolveCircleObstacle(pos: &pos, vel: &vel,
                              centre: centre, obstacleRadius: 15,
                              ballRadius: 10, restitution: 0.8)
        let dist = hypot(pos.x - 200, pos.y - 400)
        XCTAssertGreaterThanOrEqual(dist, 25 - 0.01,
                                    "Ball should be pushed to at least combined radii apart")
        XCTAssertGreaterThan(vel.dx, 0, "Velocity should be reflected away from obstacle")
    }

    func testResolveCircleObstacle_noOverlap_noChange() {
        var pos = CGPoint(x: 300, y: 400)    // 100 px from obstacle at (200, 400)
        var vel = CGVector(dx: -2, dy: 0)
        let centre = CGPoint(x: 200, y: 400)
        let beforePos = pos, beforeVel = vel
        resolveCircleObstacle(pos: &pos, vel: &vel,
                              centre: centre, obstacleRadius: 15,
                              ballRadius: 10, restitution: 0.8)
        XCTAssertEqual(pos.x, beforePos.x)
        XCTAssertEqual(pos.y, beforePos.y)
        XCTAssertEqual(vel.dx, beforeVel.dx)
        XCTAssertEqual(vel.dy, beforeVel.dy)
    }

    func testResolveCircleObstacle_ballAlreadySeparating_positionCorrectedVelocityUnchanged() {
        // Ball overlaps obstacle but is moving AWAY — dot > 0 — velocity should not be modified
        var pos = CGPoint(x: 205, y: 400)    // overlaps obstacle (dist=5 < radii=25)
        var vel = CGVector(dx: 3, dy: 0)     // moving away from obstacle
        let centre = CGPoint(x: 200, y: 400)
        resolveCircleObstacle(pos: &pos, vel: &vel,
                              centre: centre, obstacleRadius: 15,
                              ballRadius: 10, restitution: 0.8)
        // Position should still be corrected (pushed out)
        let dist = hypot(pos.x - 200, pos.y - 400)
        XCTAssertGreaterThanOrEqual(dist, 25 - 0.01)
        // Velocity should NOT be reflected (guard dot < 0 prevents it)
        XCTAssertEqual(vel.dx, 3.0, accuracy: 0.001)
        XCTAssertEqual(vel.dy, 0.0, accuracy: 0.001)
    }
}
