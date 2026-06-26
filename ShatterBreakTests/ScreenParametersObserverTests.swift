import AppKit
import Testing

@testable import ShatterBreak

@Suite("ScreenParametersObserver", .tags(.overlays))
@MainActor
struct ScreenParametersObserverTests {
    @Test("a screen-parameter change invokes the callback")
    func screenParameterChangeFiresCallback() {
        let center = NotificationCenter()
        let observer = ScreenParametersObserver(notificationCenter: center)
        var changeCount = 0

        observer.startObserving { changeCount += 1 }
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(changeCount == 1)
    }

    @Test("stopping observation silences further callbacks")
    func stopObservingSilencesCallback() {
        let center = NotificationCenter()
        let observer = ScreenParametersObserver(notificationCenter: center)
        var changeCount = 0

        observer.startObserving { changeCount += 1 }
        observer.stopObserving()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(changeCount == 0)
    }

    @Test("starting twice keeps the original callback")
    func startObservingIsIdempotent() {
        let center = NotificationCenter()
        let observer = ScreenParametersObserver(notificationCenter: center)
        var firstCount = 0
        var secondCount = 0

        observer.startObserving { firstCount += 1 }
        observer.startObserving { secondCount += 1 }
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(firstCount == 1, "The first callback stays registered.")
        #expect(secondCount == 0, "A second startObserving must not replace the callback.")
    }
}
