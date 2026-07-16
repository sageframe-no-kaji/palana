// TypeScaleTests — the pure arithmetic of the surface's text zoom (ho-13).
//
// TypeScale lives in PalanaCore so the multiply, the clamp, the step, and the
// default are verified without a running scene. The app's TextScale observable
// and Theme.font(_:) are thin readers over this math; pinning it here is what
// holds the coverage floor for the whole feature.

import Testing

@testable import PalanaCore

@Suite("TypeScale — the text-zoom math")
struct TypeScaleTests {
    @Test("scaled multiplies size by the factor")
    func scaledMultiplies() {
        #expect(TypeScale.scaled(11, by: 1.0) == 11)
        #expect(TypeScale.scaled(10, by: 1.2) == 12)
        #expect(TypeScale.scaled(13, by: 0.8) == 13 * 0.8)
    }

    @Test("clamped pins to the legible range")
    func clampedBounds() {
        #expect(TypeScale.clamped(0.5) == TypeScale.range.lowerBound)
        #expect(TypeScale.clamped(2.0) == TypeScale.range.upperBound)
        #expect(TypeScale.clamped(1.1) == 1.1)
        #expect(TypeScale.clamped(TypeScale.range.lowerBound) == TypeScale.range.lowerBound)
        #expect(TypeScale.clamped(TypeScale.range.upperBound) == TypeScale.range.upperBound)
    }

    @Test("clamped rescues a non-finite factor to the default")
    func clampedNonFinite() {
        #expect(TypeScale.clamped(.nan) == TypeScale.defaultScale)
        #expect(TypeScale.clamped(.infinity) == TypeScale.defaultScale)
        #expect(TypeScale.clamped(-.infinity) == TypeScale.defaultScale)
    }

    @Test("stepped nudges by delta and clamps back into range")
    func steppedNudges() {
        #expect(TypeScale.stepped(1.0, by: TypeScale.step) == 1.1)
        #expect(TypeScale.stepped(1.0, by: -TypeScale.step) == 0.9)
        // A step off the top clamps at the ceiling, never past it.
        #expect(
            TypeScale.stepped(TypeScale.range.upperBound, by: TypeScale.step)
                == TypeScale.range.upperBound)
        // And off the bottom clamps at the floor.
        #expect(
            TypeScale.stepped(TypeScale.range.lowerBound, by: -TypeScale.step)
                == TypeScale.range.lowerBound)
    }

    @Test("the default sits inside the range and reads as 1.0")
    func defaultIsInRange() {
        #expect(TypeScale.defaultScale == 1.0)
        #expect(TypeScale.range.contains(TypeScale.defaultScale))
    }

    @Test("ten steps up from the floor never exceed the ceiling")
    func repeatedStepsStayBounded() {
        var factor = TypeScale.range.lowerBound
        for _ in 0..<20 {
            factor = TypeScale.stepped(factor, by: TypeScale.step)
            #expect(TypeScale.range.contains(factor))
        }
        #expect(factor == TypeScale.range.upperBound)
    }
}
