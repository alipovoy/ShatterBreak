import SwiftUI
import AppKit
import Combine
import ScreenCaptureKit // Required for modern screen capture

@main
struct ShatterBreakApp: App {
    @StateObject private var timerState = TimerState()


    init() {
        // Pre-flight check on launch so the user gets prompted immediately
        // while they still have normal desktop access.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    var body: some Scene {
        MenuBarExtra("ShatterBreak", systemImage: "app.badge.clock") {
            MenuView(state: timerState)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - State Management
@MainActor
class TimerState: ObservableObject {
    @AppStorage("workDurationSecs") var workDurationSecs: Double = 1500
    @AppStorage("restDurationSecs") var restDurationSecs: Double = 300

    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isResting = false
    @Published var timeRemaining: TimeInterval = 0

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let overlayManager = OverlayManager()

    // Tracks if the system forced a pause, so we can auto-resume on wake
    private var wasAutoPausedBySystem = false

    init() {
        setupSleepObservers()
    }

    func start() {
        timeRemaining = workDurationSecs
        isRunning = true
        isPaused = false
        wasAutoPausedBySystem = false
        runTimer()
    }

    func pause() {
        isPaused = true
        timer?.cancel()
    }

    func resume() {
        isPaused = false
        runTimer()
    }

    func stop() {
        timer?.cancel()
        isRunning = false
        isPaused = false
        wasAutoPausedBySystem = false
        timeRemaining = 0
        isResting = false
        overlayManager.dismissOverlays()
    }

    private func runTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            self.timeRemaining -= 1

            if self.timeRemaining <= 0 {
                self.timer?.cancel()
                if self.isResting {
                    self.overlayManager.dismissOverlays()
                    self.isResting = false
                    self.start()
                } else {
                    self.triggerNotifyAction()
                }
            }
        }
    }

    private func triggerNotifyAction() {
        isResting = true
        timeRemaining = restDurationSecs
        overlayManager.showOverlays(state: self)
        runTimer()
    }

    // MARK: - Sleep & Display Observation
    private func setupSleepObservers() {
        let workspaceNC = NSWorkspace.shared.notificationCenter

        // 1. System Sleep
        workspaceNC.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.handleSleep() }
            .store(in: &cancellables)

        // 2. Display Sleep
        workspaceNC.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.handleSleep() }
            .store(in: &cancellables)

        // 3. System Wake
        workspaceNC.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)

        // 4. Display Wake
        workspaceNC.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)
    }

    private func handleSleep() {
        // If the timer is actively running, pause it and remember that WE paused it
        if isRunning && !isPaused {
            pause()
            wasAutoPausedBySystem = true
        }
    }

    private func handleWake() {
        // If the system wakes up and we were the ones who paused it, resume automatically
        if wasAutoPausedBySystem {
            resume()
            wasAutoPausedBySystem = false
        }
    }
}


// MARK: - Menu View (Popover Style with Validation)
struct MenuView: View {
    @ObservedObject var state: TimerState

    // Tracks which text field is currently active for input validation
    enum FocusedField {
        case work, rest
    }
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        VStack(spacing: 16) {
            // Header / Timer Display
            VStack {
                if state.isRunning || state.isPaused {
                    Text(timeString(from: state.timeRemaining))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(state.isResting ? .green : .primary)
                } else {
                    Text("Ready")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 60)

            // Main Controls for Start/Pause/Stop
            HStack(spacing: 12) {
                if state.isRunning || state.isPaused {
                    Button(action: {
                        state.isPaused ? state.resume() : state.pause()
                    }) {
                        Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button(action: { state.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                } else {
                    Button(action: { state.start() }) {
                        Label("Start Focus", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            // Configuration Sliders for durations
            VStack(alignment: .leading, spacing: 12) {
                // Work Timer Row
                Text("Work Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Image(systemName: "briefcase.fill")
                        .foregroundColor(.secondary)

                    Slider(value: logBinding(for: $state.workDurationSecs, min: 5, max: 7200), in: 0...1)

                    TextField("Secs", value: $state.workDurationSecs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .work)
                        .onSubmit { validateInputs() }

                    Text("sec")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(state.isRunning)

                // Rest Timer Row
                Text("Rest Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 4)

                HStack {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundColor(.secondary)

                    Slider(value: logBinding(for: $state.restDurationSecs, min: 5, max: 3600), in: 0...1)

                    TextField("Secs", value: $state.restDurationSecs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .rest)
                        .onSubmit { validateInputs() }

                    Text("sec")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(state.isRunning)
            }

            Divider()

            // Footer with Quit button
            HStack {
                Spacer()
                Button("Quit", ) {
                    NSApp.terminate(nil) // macOS
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
        .onChange(of: focusedField) { oldFocus, newFocus in
            if newFocus == nil {
                validateInputs()
            }
        }
    }

    // MARK: - Helpers

    private func validateInputs() {
        // Ensure work duration is within a valid range
        if state.workDurationSecs < 5 { state.workDurationSecs = 5 }
        if state.workDurationSecs > 7200 { state.workDurationSecs = 7200 }

        // Ensure rest duration is within a valid range
        if state.restDurationSecs < 5 { state.restDurationSecs = 5 }
        if state.restDurationSecs > 3600 { state.restDurationSecs = 3600 }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // Creates a logarithmic binding for the slider to provide better control over large ranges
    private func logBinding(for value: Binding<Double>, min: Double, max: Double) -> Binding<Double> {
        Binding(
            get: {
                let clampedValue = Swift.max(min, Swift.min(value.wrappedValue, max))
                return log(clampedValue / min) / log(max / min)
            },
            set: { newValue in
                let newSeconds = min * pow((max / min), newValue)
                value.wrappedValue = round(newSeconds)
            }
        )
    }
}


// MARK: - Overlay Manager
@MainActor
class OverlayManager {
    private var windows: [NSWindow] = []
    private var captureTask: Task<Void, Never>? // Manages the asynchronous screen capture process

    func showOverlays(state: TimerState) {
        captureTask?.cancel() // Cancel any ongoing capture tasks before starting a new one

        let hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

        captureTask = Task {
            var capturedImages: [CGDirectDisplayID: CGImage] = [:]

            if hasScreenRecordingPermission {
                do {
                    // Capture content from all displays, excluding desktop windows
                    let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

                    for display in shareableContent.displays {
                        if Task.isCancelled { return }

                        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = display.width
                        config.height = display.height
                        config.showsCursor = false

                        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        capturedImages[display.displayID] = cgImage
                    }
                } catch {
                    print("ScreenCaptureKit error: \(error.localizedDescription)")
                }
            }

            if Task.isCancelled { return } // Check for cancellation before creating windows

            // Create an overlay window for each screen
            for screen in NSScreen.screens {
                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )

                // Prevent AppKit from auto-releasing the window on close, as we manage its lifecycle
                window.isReleasedWhenClosed = false

                window.level = NSWindow.Level(Int(NSWindow.Level.mainMenu.rawValue) - 1) // Place below menu bar
                window.isOpaque = false
                window.backgroundColor = .clear
                window.ignoresMouseEvents = false // Disallow clicks to pass through
                window.setFrame(screen.frame, display: true)

                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                let screenshot = capturedImages[displayID]

                let hostingView = NSHostingView(rootView: OverlayView(state: state, bgImage: screenshot, hasPermission: hasScreenRecordingPermission))
                window.contentView = hostingView
                window.makeKeyAndOrderFront(nil)

                windows.append(window)
            }
        }
    }

    func dismissOverlays() {
        captureTask?.cancel() // Cancel any pending capture tasks

        windows.forEach { window in
            // Safely detach the SwiftUI view and hide the window before deallocation
            window.contentView = nil
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}


// MARK: - Overlay View
struct OverlayView: View {
    @ObservedObject var state: TimerState
    var bgImage: CGImage?
    var hasPermission: Bool

    @State private var phase = 0 // Controls animation sequence
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if hasPermission, let cgImage = bgImage {
                Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    .resizable()
                    .offset(x: phase == 1 ? shakeOffset : 0, y: phase == 1 ? -shakeOffset : 0)
            } else {
                Color.black.opacity(0.85) // Fallback if no permission or capture failed
            }

            if phase == 2 || (!hasPermission && phase > 0) {
                CrackedGlassView()

                VStack {
                    Text("Time to rest")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 5)

                    Text(timeString(from: state.timeRemaining))
                        .font(.system(size: 80, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 5)
                }
            }
        }
        // Use .task to manage the animation lifecycle, automatically cancelling on view dismissal
        .task {
            await runAnimationSequence()
        }
    }

    private func runAnimationSequence() async {
        if hasPermission {
            if Task.isCancelled { return }

            // Shake the screen
            phase = 1
            withAnimation(Animation.linear(duration: 0.05).repeatCount(40, autoreverses: true)) {
                shakeOffset = 15
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 more seconds
            if Task.isCancelled { return }

            // Shatter and display text
            phase = 2
            NSSound(named: "Glass")?.play()

        } else {
            // Fallback for denied permissions
            // The screen becomes grey immediately. We set phase = 2 to show shatters instantly without delay.
            phase = 2
            NSSound(named: "Glass")?.play()
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


struct CrackedGlassView: View {
    @State private var mainCracks = Path()
    @State private var webCracks = Path()
    @State private var shatterCenter: CGPoint = .zero
    @State private var isGenerated = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                if !isGenerated { return }

                // Render the paths
                // Dark underlay for depth (simulating the edge of thick glass)
                context.stroke(mainCracks, with: .color(.black.opacity(0.5)), lineWidth: 3)
                context.stroke(webCracks,  with: .color(.black.opacity(0.3)), lineWidth: 1.5)

                // White overlay for light catching the fracture
                context.stroke(mainCracks, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                context.stroke(webCracks,  with: .color(.white.opacity(0.6)), lineWidth: 0.5)

                // Shatter origin impact mark
                let impactRect = CGRect(x: shatterCenter.x - 5, y: shatterCenter.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: impactRect), with: .color(.white.opacity(0.9)))
            }
            .onAppear {
                generateCracks(size: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                generateCracks(size: newSize)
            }
        }
        // Ensure the Canvas doesn't block clicks from passing through if needed
        .allowsHitTesting(false)
    }

    private func generateCracks(size: CGSize) {
        if size.width == 0 || size.height == 0 { return }

        // Pick a shatter origin point near the center of the given area
        let center = CGPoint(
            x: size.width * 0.5 + CGFloat.random(in: -100...100),
            y: size.height * 0.5 + CGFloat.random(in: -100...100)
        )

        var main = Path()
        var web = Path()

        let numMainCracks = Int.random(in: 12...18)
        let maxRadius = max(size.width, size.height) * 1.2

        // Generate radial cracks shooting outwards from the center
        for i in 0..<numMainCracks {
            // Distribute angles roughly evenly, with some randomness
            let baseAngle = (Double(i) / Double(numMainCracks)) * .pi * 2.0
            let angle = baseAngle + Double.random(in: -0.2...0.2)

            var currentPoint = center
            main.move(to: currentPoint)

            var currentRadius: CGFloat = 0

            // Trace the crack outwards until it leaves the screen area
            while currentRadius < maxRadius {
                // Step length
                let step = CGFloat.random(in: 20...80)
                currentRadius += step

                // Jitter perpendicular to the crack direction
                let drift = CGFloat.random(in: -15...15)

                let nextX = center.x + currentRadius * cos(angle) + drift * sin(angle)
                let nextY = center.y + currentRadius * sin(angle) - drift * cos(angle)

                currentPoint = CGPoint(x: nextX, y: nextY)
                main.addLine(to: currentPoint)

                // Occasionally spawn smaller "web" fractures
                if CGFloat.random(in: 0...1) > 0.6 {
                    web.move(to: currentPoint)

                    let webAngle = angle + Double.random(in: -1.0...1.0)
                    let webLength = CGFloat.random(in: 15...60)

                    let webX = currentPoint.x + webLength * cos(webAngle)
                    let webY = currentPoint.y + webLength * sin(webAngle)

                    web.addLine(to: CGPoint(x: webX, y: webY))
                }
            }
        }

        DispatchQueue.main.async {
            self.shatterCenter = center
            self.mainCracks = main
            self.webCracks = web
            self.isGenerated = true
        }
    }
}
