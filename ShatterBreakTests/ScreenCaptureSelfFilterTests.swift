import Testing

@testable import ShatterBreak

@Suite("ScreenCaptureSelfFilter", .tags(.overlays))
struct ScreenCaptureSelfFilterTests {
    @Test("a matching process identifier is treated as self")
    func matchingProcessIsSelf() {
        let isSelf = ScreenCaptureSelfFilter.isSelf(
            processID: 42,
            bundleIdentifier: "com.other.app",
            currentProcessID: 42,
            currentBundleIdentifier: "dev.lipovoy.shatterbreak"
        )

        #expect(isSelf, "A process whose PID matches the current process must be excluded.")
    }

    @Test("a matching bundle identifier is treated as self")
    func matchingBundleIsSelf() {
        let isSelf = ScreenCaptureSelfFilter.isSelf(
            processID: 7,
            bundleIdentifier: "dev.lipovoy.shatterbreak",
            currentProcessID: 42,
            currentBundleIdentifier: "dev.lipovoy.shatterbreak"
        )

        #expect(isSelf, "A helper process sharing the app's bundle must be excluded.")
    }

    @Test("an unrelated application is not treated as self")
    func unrelatedApplicationIsNotSelf() {
        let isSelf = ScreenCaptureSelfFilter.isSelf(
            processID: 7,
            bundleIdentifier: "com.other.app",
            currentProcessID: 42,
            currentBundleIdentifier: "dev.lipovoy.shatterbreak"
        )

        #expect(isSelf == false, "A different application must remain in the screenshot.")
    }

    @Test("a missing current bundle identifier falls back to process matching only")
    func missingCurrentBundleUsesProcessOnly() {
        let nonMatching = ScreenCaptureSelfFilter.isSelf(
            processID: 7,
            bundleIdentifier: "dev.lipovoy.shatterbreak",
            currentProcessID: 42,
            currentBundleIdentifier: nil
        )
        #expect(nonMatching == false, "Without a current bundle ID, only the PID can identify self.")

        let matching = ScreenCaptureSelfFilter.isSelf(
            processID: 42,
            bundleIdentifier: nil,
            currentProcessID: 42,
            currentBundleIdentifier: nil
        )
        #expect(matching, "A PID match must still identify self when no bundle ID is available.")
    }
}
