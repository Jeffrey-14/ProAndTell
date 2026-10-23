//
//  ContentView.swift
//  ProAndTell
//
//  Created by Nana Yaw on 10/22/26.
//
import SwiftUI

/// Procedural recreation of the supplied 5.67-second reference.
/// iOS 16+. No images, SF Symbols, UIKit, shaders, or third-party dependencies.
struct AppleRibbonAnimation: View {
    var duration: Double = 5.67
    var speed: Double = 1
    var loops: Bool = true
    var glow: Double = 1.45
    /// Surface brightness, independent of the surrounding bloom.
    var shine: Double = 1.45
    var logoScale: CGFloat = 1
    /// Set to a reference-video timestamp to inspect a stationary frame.
    var previewTime: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || scenePhase != .active || previewTime != nil || finished)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(start)) * max(0.01, speed)
            let cycle = max(0.1, duration)
            let phase = (loops ? elapsed.truncatingRemainder(dividingBy: cycle) : min(elapsed, cycle)) / cycle
            let time = previewTime.map { min(5.67, max(0, $0)) } ?? (reduceMotion ? 2.8 : (finished ? 5.67 : phase * 5.67))

            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let scale = min(size.width, size.height) / 720 * logoScale
                guard scale > 0 else { return }
                context.translateBy(x: (size.width - 720 * scale) / 2, y: (size.height - 720 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                drawLogo(context: &context, time: time)
            }
        }
        .task(id: PlaybackSettings(duration: duration, speed: speed, loops: loops, scenePhase: scenePhase, previewTime: previewTime, reduceMotion: reduceMotion)) {
            guard scenePhase == .active else { return }
            start = Date()
            finished = false
            guard !loops, previewTime == nil, !reduceMotion else { return }
            let seconds = min(86_400, max(0.1, duration) / max(0.01, speed))
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                finished = true
            } catch { /* View disappeared or playback settings changed. */ }
        }
        .accessibilityLabel("Animated Apple logo made of glowing silver strands")
    }

    private struct PlaybackSettings: Equatable {
        var duration: Double
        var speed: Double
        var loops: Bool
        var scenePhase: ScenePhase
        var previewTime: Double?
        var reduceMotion: Bool
    }

    private struct VisibleStrand {
        let strand: RibbonGeometry.Strand
        let tail: Path
        let body: Path
        let head: Path
        let headStart: CGFloat
        let end: CGFloat
    }

    private func drawLogo(context: inout GraphicsContext, time: Double) {
        let bodyEnd = MotionTrack.reveal.value(at: time)
        let bodyStart = MotionTrack.erase.value(at: time)
        let leafEnd = MotionTrack.leaf.value(at: time)
        let leafStart = CGFloat(Self.smooth(4.03, 4.72, time))
        let opacity = Self.smooth(0, 0.12, time) * (1 - Self.smooth(4.30, 5.04, time))
        guard opacity > 0.001, bodyEnd > bodyStart else { return }
        context.opacity = opacity
        context.blendMode = .plusLighter

        var visible: [VisibleStrand] = []
        visible.reserveCapacity(RibbonGeometry.body.count)
        var bloomPath = Path()
        var sheenPath = Path()
        let tailOpacity = 1 - Self.smooth(1.35, 2.70, time)
        let headOpacity = 0.74 * (1 - Self.smooth(0.92, 1, Double(bodyEnd)))

        for (index, strand) in RibbonGeometry.body.enumerated() {
            let end = max(0, min(1, bodyEnd - 0.012 * (1 - strand.depth) * sin(.pi * bodyEnd)))
            let start = min(1, bodyStart + strand.depth * 0.07 * sin(.pi * bodyStart))
            guard end > start else { continue }
            let tail = tailOpacity > 0.001 ? strand.section(from: start, to: min(end, RibbonGeometry.tailFraction)) : Path()
            let body = strand.section(from: max(start, RibbonGeometry.tailFraction), to: end)
            let headStart = max(start, end - 0.105)
            let head = headOpacity > 0.001 && index % 9 != 0 ? strand.section(from: headStart, to: end) : Path()
            visible.append(VisibleStrand(strand: strand, tail: tail, body: body, head: head, headStart: headStart, end: end))
            if index % 3 == 0 && strand.depth < 0.42 { sheenPath.addPath(body) }
            if index % 5 == 0 {
                // Exclude the faint bite tail from bloom; it was too bright before.
                bloomPath.addPath(body)
                if !head.isEmpty { bloomPath.addPath(head) }
            }
        }

        var leaves: [(RibbonGeometry.Strand, Path)] = []
        leaves.reserveCapacity(RibbonGeometry.leaf.count)
        if leafEnd > leafStart {
            for (index, strand) in RibbonGeometry.leaf.enumerated() {
                let path = strand.section(from: leafStart, to: leafEnd)
                leaves.append((strand, path))
                if index % 3 == 0 { bloomPath.addPath(path) }
                if index % 3 == 0 && strand.depth < 0.45 { sheenPath.addPath(path) }
            }
        }

        // One compound path per blur pass, rather than filtering each stroke.
        if glow > 0 && !bloomPath.isEmpty {
            for pass in 0..<2 {
                var bloom = context
                bloom.opacity *= (pass == 0 ? 0.21 : 0.16) * glow
                bloom.addFilter(.blur(radius: pass == 0 ? 16 : 4.5))
                bloom.stroke(bloomPath, with: .color(Color(red: 0.60, green: 0.77, blue: 1)), lineWidth: pass == 0 ? 8 : 4)
            }
        }

        // Restrained outer sheen. Keep the inner filaments unblurred and avoid
        // flooding the gaps between individual strokes with additive light.
        if shine > 0 && !sheenPath.isEmpty {
            var sheen = context
            sheen.opacity *= 0.09 * shine
            sheen.addFilter(.blur(radius: 1.1))
            sheen.stroke(sheenPath, with: RibbonGeometry.sheenShading, lineWidth: 1.8)
        }

        var surface = context
        surface.opacity *= max(0, shine)
        for item in visible {
            let strand = item.strand
            if !item.tail.isEmpty {
                var tailContext = surface
                tailContext.opacity *= tailOpacity
                tailContext.stroke(item.tail, with: strand.tailShading, style: strand.style)
            }
            if !item.body.isEmpty { surface.stroke(item.body, with: strand.shading, style: strand.style) }
            if !item.head.isEmpty {
                var headContext = context
                headContext.opacity *= headOpacity
                headContext.stroke(item.head, with: .linearGradient(RibbonGeometry.headGradient, startPoint: strand.point(at: item.headStart), endPoint: strand.point(at: item.end)), lineWidth: strand.width + 0.15)
            }
        }

        for (strand, path) in leaves {
            surface.stroke(path, with: strand.shading, style: strand.style)
        }
    }

    private static func smooth(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let x = min(1, max(0, (value - lower) / (upper - lower)))
        return x * x * (3 - 2 * x)
    }
}

private enum RibbonGeometry {
    // The first cubic is an entrance trail, not part of the finished silhouette.
    // 0.16 reaches the lower lip of the bite in the shared progress coordinate.
    static let tailFraction: CGFloat = 0.16
    static let sheenShading = GraphicsContext.Shading.linearGradient(Gradient(stops: [.init(color: Color(red: 0.84, green: 0.94, blue: 1), location: 0), .init(color: Color(red: 0.76, green: 0.88, blue: 1), location: 0.30), .init(color: Color(red: 0.38, green: 0.55, blue: 0.74).opacity(0.45), location: 0.70), .init(color: Color(red: 0.76, green: 0.86, blue: 1).opacity(0.80), location: 1)]), startPoint: CGPoint(x: 350, y: 115), endPoint: CGPoint(x: 350, y: 550))
    static let headGradient = Gradient(colors: [Color(red: 0.70, green: 0.82, blue: 1).opacity(0.15), Color(red: 1, green: 1, blue: 1).opacity(0.9)])

    struct Strand {
        let path: Path
        let settledTail: Path
        let settledBody: Path
        let samples: [CGPoint]
        let depth: CGFloat
        let width: CGFloat
        let style: StrokeStyle
        let shading: GraphicsContext.Shading
        let tailShading: GraphicsContext.Shading

        func point(at fraction: CGFloat) -> CGPoint {
            let position = min(1, max(0, fraction)) * CGFloat(samples.count - 1)
            let index = min(samples.count - 2, Int(position))
            let t = position - CGFloat(index)
            let a = samples[index]
            let b = samples[index + 1]
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        func section(from start: CGFloat, to end: CGFloat) -> Path {
            let lower = min(1, max(0, start))
            let upper = min(1, max(0, end))
            guard upper > lower else { return Path() }
            if lower == 0 && upper == 1 { return path }
            if lower == 0 && upper == RibbonGeometry.tailFraction { return settledTail }
            if lower == RibbonGeometry.tailFraction && upper == 1 { return settledBody }
            return Self.slice(samples, from: lower, to: upper)
        }

        // All strands share a reference-contour progress coordinate, keeping
        // the leading edge aligned across the ribbon. Slice only visible samples.
        static func slice(_ samples: [CGPoint], from lower: CGFloat, to upper: CGFloat) -> Path {
            guard upper > lower else { return Path() }
            let last = samples.count - 1
            func interpolate(_ fraction: CGFloat) -> CGPoint {
                let position = fraction * CGFloat(last)
                let index = min(last - 1, Int(position))
                let t = position - CGFloat(index)
                let a = samples[index]
                let b = samples[index + 1]
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            var result = Path()
            result.move(to: interpolate(lower))
            let firstIndex = Int(lower * CGFloat(last)) + 1
            let endIndex = Int(ceil(upper * CGFloat(last)))
            if firstIndex < endIndex {
                for index in firstIndex..<endIndex { result.addLine(to: samples[index]) }
            }
            result.addLine(to: interpolate(upper))
            return result
        }
    }

    struct Curve {
        let p0: CGPoint
        let p1: CGPoint
        let p2: CGPoint
        let p3: CGPoint

        init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) {
            p0 = CGPoint(x: x0, y: y0)
            p1 = CGPoint(x: x1, y: y1)
            p2 = CGPoint(x: x2, y: y2)
            p3 = CGPoint(x: x3, y: y3)
        }

        func point(_ t: Double) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x, y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
        }
    }

    // Matching cubic segments bound the ribbon. Interpolating the two boundaries
    // preserves the bite and bottom lobes; scaled copies of a logo do not.
    private static let outer = [
        Curve(500, 278, 459, 318, 463, 386, 525, 434),
        Curve(525, 434, 540, 442, 477, 555, 418, 550),
        Curve(418, 550, 393, 551, 377, 533, 356, 534),
        Curve(356, 534, 330, 533, 313, 553, 288, 549),
        Curve(288, 549, 234, 545, 181, 441, 178, 367),
        Curve(178, 367, 170, 293, 206, 232, 265, 223),
        Curve(265, 223, 306, 215, 330, 240, 356, 241),
        Curve(356, 241, 382, 241, 409, 218, 440, 220),
        Curve(440, 220, 472, 220, 496, 237, 514, 256)
    ]
    private static let inner = [
        Curve(500, 278, 435, 318, 390, 365, 447, 396),
        Curve(447, 396, 459, 410, 434, 477, 405, 479),
        Curve(405, 479, 385, 480, 373, 472, 356, 473),
        Curve(356, 473, 336, 472, 324, 484, 307, 480),
        Curve(307, 480, 277, 475, 250, 410, 249, 367),
        Curve(249, 367, 244, 325, 265, 295, 295, 294),
        Curve(295, 294, 317, 291, 337, 307, 356, 307),
        Curve(356, 307, 379, 308, 396, 292, 414, 295),
        Curve(414, 295, 428, 297, 440, 312, 442, 323)
    ]

    static let body: [Strand] = makeStrands(outer: outer, inner: inner, count: 82, leaf: false)
    static let leaf: [Strand] = makeStrands(outer: [Curve(354, 213, 349, 167, 396, 122, 439, 115), Curve(439, 115, 443, 158, 405, 211, 354, 213)], inner: [Curve(354, 213, 354, 195, 374, 177, 389, 173), Curve(389, 173, 391, 188, 372, 207, 354, 213)], count: 34, leaf: true)

    private static func makeStrands(outer: [Curve], inner: [Curve], count: Int, leaf: Bool) -> [Strand] {
        // Build one common distance coordinate. Independently normalizing every
        // strand makes inner strands run ahead around tight corners.
        var reference: [CGPoint] = []
        reference.reserveCapacity(outer.count * 48 + 1)
        for segment in outer.indices {
            for step in 0..<48 {
                let t = Double(step) / 48
                let a = outer[segment].point(t)
                let b = inner[segment].point(t)
                reference.append(CGPoint(x: a.x + (b.x - a.x) * 0.15, y: a.y + (b.y - a.y) * 0.15))
            }
        }
        let referenceEndA = outer.last!.p3
        let referenceEndB = inner.last!.p3
        reference.append(CGPoint(x: referenceEndA.x + (referenceEndB.x - referenceEndA.x) * 0.15, y: referenceEndA.y + (referenceEndB.y - referenceEndA.y) * 0.15))
        var distances = [CGFloat](repeating: 0, count: reference.count)
        for index in 1..<reference.count {
            distances[index] = distances[index - 1] + hypot(reference[index].x - reference[index - 1].x, reference[index].y - reference[index - 1].y)
        }
        return (0..<count).map { index in
            let depth = Double(index) / Double(count - 1)
            let variation = noise(index + 7)
            var raw: [CGPoint] = []
            raw.reserveCapacity(outer.count * 48 + 1)
            for segment in outer.indices {
                for step in 0..<48 {
                    let t = Double(step) / 48
                    let a = outer[segment].point(t)
                    let b = inner[segment].point(t)
                    let envelope = sin(.pi * (Double(segment) + t) / Double(outer.count))
                    let ripple = sin((Double(segment) + t) * 7 + depth * 10) * 0.16 * envelope
                    raw.append(CGPoint(x: a.x + (b.x - a.x) * depth + ripple, y: a.y + (b.y - a.y) * depth + ripple * 0.6))
                }
            }
            let a = outer.last!.p3
            let b = inner.last!.p3
            raw.append(CGPoint(x: a.x + (b.x - a.x) * depth, y: a.y + (b.y - a.y) * depth))
            let points = resample(raw, distances: distances, count: leaf ? 128 : 384)
            var path = Path()
            path.addLines(points)
            let colour: Color
            switch index {
            case 14: colour = Color(red: 1, green: 0.72, blue: 0.25)
            case 22: colour = Color(red: 1, green: 0.22, blue: 0.12)
            case 57: colour = Color(red: 0.27, green: 0.58, blue: 1)
            default: colour = Color(red: 0.78 + variation * 0.20, green: 0.88 + variation * 0.10, blue: 1)
            }
            // Separate crisp filaments from the soft sheen. Most strokes stay
            // narrower than their spacing; intermittent accents remain visible
            // in the inner half instead of filling the ribbon with uniform light.
            let isAccent = index % 4 == 1
            let edgeLight = 0.20 + 0.80 * pow(1 - depth, 1.2)
            let accentLight = isAccent ? 0.24 * sin(.pi * depth) : 0
            let brightness = min(1, (0.32 + variation * 0.68) * edgeLight + accentLight + (index < 3 ? 0.20 : 0))
            let width: CGFloat = isAccent ? (leaf ? 0.78 : 0.95) : 0.40 + noise(index + 91) * 0.26
            let shading: GraphicsContext.Shading
            if leaf {
                shading = .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.76, blue: 0.94).opacity(brightness * 0.38), Color(red: 0.92, green: 0.98, blue: 1).opacity(brightness)]), startPoint: CGPoint(x: 354, y: 214), endPoint: CGPoint(x: 438, y: 115))
            } else {
                shading = .linearGradient(Gradient(stops: [.init(color: colour.opacity(brightness), location: 0), .init(color: colour.opacity(brightness * 0.98), location: 0.24), .init(color: colour.opacity(brightness * 0.34), location: 0.60), .init(color: colour.opacity(brightness * 0.60), location: 1)]), startPoint: CGPoint(x: 310, y: 220), endPoint: CGPoint(x: 380, y: 555))
            }
            let tailPoint = points[Int(CGFloat(points.count - 1) * tailFraction)]
            let tailShading = GraphicsContext.Shading.linearGradient(Gradient(stops: [.init(color: colour.opacity(brightness * 0.015), location: 0), .init(color: colour.opacity(brightness * 0.04), location: 0.5), .init(color: colour.opacity(brightness * 0.38), location: 1)]), startPoint: points[0], endPoint: tailPoint)
            return Strand(path: path, settledTail: Strand.slice(points, from: 0, to: tailFraction), settledBody: Strand.slice(points, from: tailFraction, to: 1), samples: points, depth: CGFloat(depth), width: width, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round), shading: shading, tailShading: tailShading)
        }
    }

    private static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 127.1 + 311.7) * 43758.5453
        return value - floor(value)
    }

    private static func resample(_ points: [CGPoint], distances: [CGFloat], count: Int) -> [CGPoint] {
        let total = distances.last!
        var segment = 1
        return (0..<count).map { index in
            let target = total * CGFloat(index) / CGFloat(count - 1)
            while segment < points.count - 1 && distances[segment] < target { segment += 1 }
            let fraction = (target - distances[segment - 1]) / max(0.0001, distances[segment] - distances[segment - 1])
            let a = points[segment - 1]
            let b = points[segment]
            return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        }
    }
}

struct AppleRibbonDemo: View {
    var body: some View {
        ZStack {
            AppleRibbonAnimation()
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(1.25)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AppleRibbonDemo()
}

private struct MotionTrack {
    let keys: [(time: CGFloat, value: CGFloat)]

    func value(at time: Double) -> CGFloat {
        let x = CGFloat(time)
        guard x > keys[0].time else { return keys[0].value }
        guard x < keys[keys.count - 1].time else { return keys[keys.count - 1].value }
        var index = 0
        while index + 1 < keys.count - 1 && x > keys[index + 1].time { index += 1 }
        let a = keys[index]
        let b = keys[index + 1]
        let length = b.time - a.time
        let t = (x - a.time) / length
        let t2 = t * t
        let t3 = t2 * t
        let result = (2*t3 - 3*t2 + 1)*a.value + (t3 - 2*t2 + t)*length*tangent(index) + (-2*t3 + 3*t2)*b.value + (t3 - t2)*length*tangent(index + 1)
        return min(b.value, max(a.value, result))
    }

    private func tangent(_ index: Int) -> CGFloat {
        func slope(_ i: Int) -> CGFloat { (keys[i + 1].value - keys[i].value) / (keys[i + 1].time - keys[i].time) }
        if index == 0 { return slope(0) }
        if index == keys.count - 1 { return 0 }
        let left = slope(index - 1)
        let right = slope(index)
        guard left > 0, right > 0 else { return 0 }
        return 2 * left * right / (left + right)
    }

    // Fractions estimated from luminance along the reference contour, rather
    // than assuming that draw progress is linear in elapsed time.
    static let reveal = MotionTrack(keys: [(0, 0), (0.0334, 0.012), (0.0667, 0.026), (0.1001, 0.039), (0.1335, 0.0711), (0.1668, 0.1101), (0.2669, 0.2112), (0.4004, 0.3163), (0.5339, 0.4174), (0.6673, 0.5065), (0.8008, 0.5816), (1.001, 0.6737), (1.2012, 0.7508), (1.4014, 0.8098), (1.6016, 0.8559), (1.8018, 0.8949), (2.002, 0.9269), (2.2022, 0.952), (2.4024, 0.973), (2.6026, 0.989), (2.8028, 1)])
    static let erase = MotionTrack(keys: [(3.84, 0), (4.004, 0.12), (4.137, 0.203), (4.271, 0.247), (4.404, 0.380), (4.538, 0.521), (4.671, 0.701), (4.805, 0.87), (5.04, 1)])
    static let leaf = MotionTrack(keys: [(1.62, 0), (1.80, 0.26), (1.97, 0.56), (2.14, 0.84), (2.30, 1)])
}
