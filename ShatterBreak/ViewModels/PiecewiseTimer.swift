struct PiecewiseTimer: Sendable {
    static let anchors: [SliderAnchor] = [
        SliderAnchor(stop: 0.0, value: 5),
        SliderAnchor(stop: 0.1, value: 30),
        SliderAnchor(stop: 0.2, value: 60),
        SliderAnchor(stop: 0.3, value: 300),
        SliderAnchor(stop: 0.4, value: 600),
        SliderAnchor(stop: 0.5, value: 900),
        SliderAnchor(stop: 0.6, value: 1500),
        SliderAnchor(stop: 0.7, value: 2700),
        SliderAnchor(stop: 0.8, value: 3300),
        SliderAnchor(stop: 0.9, value: 5400),
        SliderAnchor(stop: 1.0, value: 7200)
    ]

    static func seconds(from t: Double) -> Double {
        guard anchors.count >= 2 else { return anchors.first?.value ?? 0 }

        for i in 0..<anchors.count - 1 {
            let start = anchors[i]
            let end = anchors[i + 1]

            if t <= end.stop {
                let localT = (t - start.stop) / (end.stop - start.stop)
                return start.value + localT * (end.value - start.value)
            }
        }
        return anchors.last?.value ?? 0
    }

    static func position(from seconds: Double) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }

        if seconds <= first.value { return first.stop }
        if seconds >= last.value { return last.stop }

        for i in 0..<anchors.count - 1 {
            let start = anchors[i]
            let end = anchors[i + 1]

            if seconds <= end.value {
                let localT = (seconds - start.value) / (end.value - start.value)
                return start.stop + localT * (end.stop - start.stop)
            }
        }
        return last.stop
    }
}
