// A declaration is a constant, often a `static let`, so it can't throw: the Tweaks plugin checks it
// as `installTweaks` shows it, and the receiver's tweaks capability as it is made. Here, that a
// declaration they would refuse still makes a tweak rather than trapping, and reads as its default.
@testable import DebugDrawerTweaks
import Testing

@Suite
struct TweakDeclarationCheckTests {
    @Test("A stepper whose default is outside its range is made, and reads as that default")
    func stepperDefaultOutsideRange() {
        let expected = 0

        let sut = Tweak.stepper("Timeout", key: "timeout", default: expected, in: 1 ... 10)

        #expect(sut.defaultValue == expected)
        #expect(sut.value(from: nil) == expected)
    }

    @Test("A stepper whose step isn't positive is made, with that step")
    func stepperStepNotPositive() {
        let expected = TweakControl.stepper(range: 1 ... 10, step: 0)

        let sut = Tweak.stepper("Timeout", key: "timeout", default: 5, in: 1 ... 10, step: 0)

        #expect(sut.control == expected)
    }

    @Test("A string picker whose default isn't one of its options is made, and reads as that default")
    func pickerDefaultNotAnOption() {
        let expected = "apac"

        let sut = Tweak.picker("Region", key: "region", options: ["us", "eu"], default: expected)

        #expect(sut.value(from: .string("us")) == "us")
        #expect(sut.value(from: nil) == expected)
    }

    @Test("A string picker with no options is made, and reads as its default")
    func pickerNoOptions() {
        let expected = "us"

        let sut = Tweak.picker("Region", key: "region", options: [], default: expected)

        #expect(sut.value(from: .string("eu")) == expected)
    }
}
