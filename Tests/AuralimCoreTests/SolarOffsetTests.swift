import Testing
@testable import AuralimCore

struct SolarOffsetTests {
    @Test
    func testPreciseInputAndValidation() {
        #expect(SolarOffset.parse(" -37 ") == -37)
        #expect(SolarOffset.parse("+42") == 42)
        #expect(SolarOffset.parse("−18") == -18)
        #expect(SolarOffset.parse("999") == 120)
        #expect(SolarOffset.parse("-999") == -120)
        for text in ["", "-", "+", "1.5", "abc", "999999999999999999999999"] {
            #expect(SolarOffset.parse(text) == nil)
        }
    }

    @Test
    func testSliderAndInputRoundTripAtEveryMinute() {
        for minute in -120...120 {
            #expect(SolarOffset.minutes(forSliderPosition: SolarOffset.sliderPosition(for: minute)) == minute)
        }
        #expect(SolarOffset.minutes(forSliderPosition: 0) == 0)
        #expect(SolarOffset.minutes(forSliderPosition: -120) == 120)
        #expect(SolarOffset.minutes(forSliderPosition: 120) == -120)
    }
}
