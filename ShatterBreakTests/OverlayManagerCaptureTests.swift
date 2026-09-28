import AppKit
import Testing

@testable import ShatterBreak

@Suite("OverlayManager capture", .tags(.overlays), .timeLimit(.minutes(1)))
@MainActor
struct OverlayManagerCaptureTests {
    @Test("a capture that outlives its break does not paint the next one")
    func staleCaptureIsDropped() async throws {
        let environment = TestEnvironment()
        let screens = StubScreens([StubScreens.display(1)])
        let image = try TestImage.make(width: 4, height: 4)
        let captures = HeldCaptures()
        let manager = OverlayManager(
            defaults: environment.defaults,
            screens: { screens.screens },
            capture: { displayIDs in
                await captures.wait()
                return Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, image) })
            },
            isDisplayAwake: { _ in true },
            hasScreenRecordingPermission: { true },
            directCaptureAccess: { .allowed }
        )
        defer { manager.dismiss() }

        manager.show(environment.makeTimerState(), style: .animated)
        let firstBreak = manager.captureTasks
        await captures.held(1)
        manager.dismiss()
        manager.show(environment.makeTimerState(), style: .animated)
        await captures.held(2)

        captures.releaseOldest()
        for task in firstBreak { await task.value }
        #expect(manager.overlayStates[1]?.backgroundImage == nil)
        #expect(manager.overlayStates[1]?.phase == .plain)

        let secondBreak = manager.captureTasks
        captures.releaseAll()
        for task in secondBreak { await task.value }
        #expect(manager.overlayStates[1]?.backgroundImage === image, "Its own capture still lands.")
    }
}

/// Captures that finish only when the test says so, oldest first.
@MainActor
private final class HeldCaptures {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Bounded, so a regression reports a failure instead of hanging.
    func held(_ count: Int) async {
        for _ in 0..<100 where waiting.count < count {
            await Task.yield()
        }
    }

    func releaseOldest() {
        guard waiting.isEmpty == false else { return }
        waiting.removeFirst().resume()
    }

    func releaseAll() {
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}
