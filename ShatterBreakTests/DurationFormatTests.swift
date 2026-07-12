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

struct StepperStepCase: Sendable {
    let seconds: Double
    let descending: Bool
    let expectedStep: Double
}

@Suite("DurationFormat", .tags(.parsing))
struct DurationFormatTests {
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
        ManualInputCase(input: "9999h", initialValue: 1500, expectedValue: 7200, expectedDisplay: "2h 0m")
    ])
    func applyingAcceptedInputUpdatesAndNormalizes(_ testCase: ManualInputCase) {
        let value = DurationFormat.applying(
            input: testCase.input,
            to: testCase.initialValue,
            min: DurationBounds.minimumSecs,
            max: DurationBounds.workMaximumSecs
        )

        #expect(value == testCase.expectedValue, "Accepted input should update the backing duration.")
        #expect(
            DurationFormat.friendly(value) == testCase.expectedDisplay,
            "Accepted input should normalize the display string."
        )
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
        InvalidManualInputCase(input: "1h-5m")
    ])
    func applyingRejectedInputPreservesPreviousValue(_ testCase: InvalidManualInputCase) {
        let accepted = DurationFormat.applying(
            input: "25:07",
            to: 5,
            min: DurationBounds.minimumSecs,
            max: DurationBounds.workMaximumSecs
        )
        #expect(accepted == 1507, "The initial valid value should parse before invalid-input checks.")
        #expect(
            DurationFormat.friendly(accepted) == "25:07",
            "The initial valid display should normalize before invalid-input checks."
        )

        let afterInvalid = DurationFormat.applying(
            input: testCase.input,
            to: accepted,
            min: DurationBounds.minimumSecs,
            max: DurationBounds.workMaximumSecs
        )
        #expect(afterInvalid == 1507, "Invalid input should preserve the previous parsed value.")
        #expect(
            DurationFormat.friendly(afterInvalid) == "25:07",
            "Invalid input should preserve the previous display value."
        )
    }

    @Test(arguments: PiecewiseTimer.anchors)
    func piecewiseTimerRoundTripsAnchors(_ anchor: SliderAnchor) {
        #expect(
            PiecewiseTimer.seconds(from: anchor.stop) == anchor.value,
            "Each slider anchor should map back to its duration."
        )
        #expect(
            PiecewiseTimer.position(from: anchor.value) == anchor.stop,
            "Each anchor duration should map back to its slider stop."
        )
    }

    @Test(arguments: [
        SliderSnapCase(rawSeconds: 33, expectedValue: 35),
        SliderSnapCase(rawSeconds: 73, expectedValue: 60),
        SliderSnapCase(rawSeconds: 615, expectedValue: 600),
        SliderSnapCase(rawSeconds: 1490, expectedValue: 1500)
    ])
    func snapsSliderMovementToExpectedStep(_ testCase: SliderSnapCase) {
        // Mirror the slider binding: a duration is mapped to a position and back before snapping.
        let rawFromSlider = PiecewiseTimer.seconds(from: PiecewiseTimer.position(from: testCase.rawSeconds))
        let snapped = DurationFormat.snap(
            rawSeconds: rawFromSlider,
            min: DurationBounds.minimumSecs,
            max: DurationBounds.workMaximumSecs
        )

        #expect(snapped == testCase.expectedValue, "Slider movement should snap to the expected duration step.")
    }

    @Test(arguments: [
        StepperStepCase(seconds: 30, descending: false, expectedStep: 5),
        StepperStepCase(seconds: 60, descending: false, expectedStep: 60),
        StepperStepCase(seconds: 60, descending: true, expectedStep: 5),
        StepperStepCase(seconds: 300, descending: false, expectedStep: 60),
        StepperStepCase(seconds: 600, descending: false, expectedStep: 300),
        StepperStepCase(seconds: 600, descending: true, expectedStep: 60),
        StepperStepCase(seconds: 900, descending: true, expectedStep: 300)
    ])
    func stepFollowsSnapScaleForDirection(_ testCase: StepperStepCase) {
        #expect(
            DurationFormat.step(from: testCase.seconds, descending: testCase.descending) == testCase.expectedStep,
            "Stepper adjustments should follow the snap scale for their direction."
        )
    }

    @Test("clock formatting uses MM:SS without capping minutes")
    func clockUsesUncappedMinutes() {
        #expect(DurationFormat.clock(3900) == "65:00", "Clock formatting should keep raw minutes for editing.")
    }

    @Test("friendly formatting uses a reader-friendly style above an hour")
    func friendlyUsesHourMinuteStyle() {
        #expect(DurationFormat.friendly(3900) == "1h 5m", "Friendly formatting should read as hours and minutes.")
    }
}
