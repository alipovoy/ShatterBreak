import SwiftUI
import Testing

@testable import ShatterBreak

struct ManualInputCase: Sendable {
    let input: String
    let initialValue: Double
    let expectedValue: Double
    let expectedDisplay: String
}

struct InvalidManualInputCase: Sendable {
    let input: String
}

struct SliderSnapCase: Sendable {
    let rawSeconds: Double
    let expectedValue: Double
}

@Suite("DurationSliderViewModel", .tags(.parsing))
struct DurationSliderViewModelTests {
    @Test(arguments: [
        ManualInputCase(input: "1h", initialValue: 1500, expectedValue: 3600, expectedDisplay: "1h 0m"),
        ManualInputCase(input: "1m", initialValue: 1500, expectedValue: 60, expectedDisplay: "01:00"),
        ManualInputCase(input: "1h5m", initialValue: 1500, expectedValue: 3900, expectedDisplay: "1h 5m"),
        ManualInputCase(input: "1h 5m", initialValue: 1500, expectedValue: 3900, expectedDisplay: "1h 5m"),
        ManualInputCase(input: "1:05", initialValue: 1500, expectedValue: 65, expectedDisplay: "01:05"),
        ManualInputCase(input: "1:5", initialValue: 1500, expectedValue: 65, expectedDisplay: "01:05"),
        ManualInputCase(input: "1:60", initialValue: 1500, expectedValue: 120, expectedDisplay: "02:00"),
        ManualInputCase(input: "1:02:03", initialValue: 1500, expectedValue: 3723, expectedDisplay: "1h 2m 3s"),
        ManualInputCase(input: "1:00:60", initialValue: 1500, expectedValue: 3660, expectedDisplay: "1h 1m"),
        ManualInputCase(input: "1:60:00", initialValue: 1500, expectedValue: 7200, expectedDisplay: "2h 0m"),
        ManualInputCase(input: "9999h", initialValue: 1500, expectedValue: 7200, expectedDisplay: "2h 0m"),
    ])
    @MainActor
    func updateValueFromInputAppliesAcceptedInput(_ testCase: ManualInputCase) {
        let viewModel = DurationSliderViewModel()
        var value = testCase.initialValue
        viewModel.manualInput = testCase.input

        viewModel.updateValueFromInput(currentValue: &value, min: 5, max: 7200)

        #expect(value == testCase.expectedValue)
        #expect(viewModel.manualInput == testCase.expectedDisplay)
    }

    @Test(arguments: [
        InvalidManualInputCase(input: ""),
        InvalidManualInputCase(input: ":"),
        InvalidManualInputCase(input: ":30"),
        InvalidManualInputCase(input: "1:"),
        InvalidManualInputCase(input: "::"),
        InvalidManualInputCase(input: "1::5"),
        InvalidManualInputCase(input: "1:05:"),
        InvalidManualInputCase(input: "1:2:3:4"),
        InvalidManualInputCase(input: "1.5:30"),
        InvalidManualInputCase(input: "1:05.5"),
        InvalidManualInputCase(input: "+1:05"),
        InvalidManualInputCase(input: "-1:05"),
        InvalidManualInputCase(input: "bogus"),
        InvalidManualInputCase(input: "10+1"),
        InvalidManualInputCase(input: "5d"),
        InvalidManualInputCase(input: "10 10"),
        InvalidManualInputCase(input: "1 h"),
        InvalidManualInputCase(input: "1m30"),
        InvalidManualInputCase(input: "1h-5m"),
    ])
    @MainActor
    func updateValueFromInputPreservesPreviousValueAfterRejectedInput(_ testCase: InvalidManualInputCase) {
        let viewModel = DurationSliderViewModel()
        var value = 5.0
        viewModel.manualInput = "25:07"

        viewModel.updateValueFromInput(currentValue: &value, min: 5, max: 7200)

        #expect(value == 1507)
        #expect(viewModel.manualInput == "25:07")

        viewModel.manualInput = testCase.input

        viewModel.updateValueFromInput(currentValue: &value, min: 5, max: 7200)

        #expect(value == 1507)
        #expect(viewModel.manualInput == "25:07")
    }

    @Test(arguments: PiecewiseTimer.anchors)
    func piecewiseTimerRoundTripsAnchors(_ anchor: SliderAnchor) {
        #expect(PiecewiseTimer.seconds(from: anchor.stop) == anchor.value)
        #expect(PiecewiseTimer.position(from: anchor.value) == anchor.stop)
    }

    @Test(arguments: [
        SliderSnapCase(rawSeconds: 33, expectedValue: 35),
        SliderSnapCase(rawSeconds: 73, expectedValue: 60),
        SliderSnapCase(rawSeconds: 615, expectedValue: 600),
        SliderSnapCase(rawSeconds: 1490, expectedValue: 1500),
    ])
    @MainActor
    func sliderBindingSnapsToExpectedStep(_ testCase: SliderSnapCase) {
        let viewModel = DurationSliderViewModel()
        var value = 1500.0
        let binding = Binding(
            get: { value },
            set: { value = $0 }
        )
        let sliderBinding = viewModel.sliderBinding(for: binding, min: 5, max: 7200)

        sliderBinding.wrappedValue = PiecewiseTimer.position(from: testCase.rawSeconds)

        #expect(value == testCase.expectedValue)
    }

    @Test("syncManualInput uses MM:SS while the field is focused")
    @MainActor
    func syncManualInputFocusedUsesClockStyle() {
        let viewModel = DurationSliderViewModel()

        viewModel.syncManualInput(with: 3900, isInputFocused: true)

        #expect(viewModel.manualInput == "65:00")
    }

    @Test("syncManualInput uses friendly formatting when the field is not focused")
    @MainActor
    func syncManualInputUnfocusedUsesFriendlyStyle() {
        let viewModel = DurationSliderViewModel()

        viewModel.syncManualInput(with: 3900, isInputFocused: false)

        #expect(viewModel.manualInput == "1h 5m")
    }
}
