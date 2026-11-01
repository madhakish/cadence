import CadenceCore
import Metal
import SceneKit
import SwiftUI
import UIKit

/// DEBUG-only visual QA for the barbell studio: renders a fixed matrix of
/// loadouts × themes × shots with the production renderer, writes each PNG
/// to tmp/render-lab, and shows them. Launched by
/// `--render-lab`; Release builds never reach it.
enum RenderLab {
    static var isRequested: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--render-lab")
#else
        false
#endif
    }

    struct Item {
        let name: String
        let request: StudioRenderer.Request
    }

    static var framingOnly: Bool { ProcessInfo.processInfo.arguments.contains("--studio-framing-proof") }
    static var framingLoadout: Loadout {
        Loadout(bar: .bar45lb, perSide: [PlateCount(plate: Plate(value: 45, unit: .lb), count: 5)], collarLb: 0)
    }

    static var matrix: [Item] {
        func lb(_ v: Double) -> Plate { Plate(value: v, unit: .lb) }
        func kg(_ v: Double) -> Plate { Plate(value: v, unit: .kg) }
        func load(_ bar: Bar, _ plates: [Plate], collar: Double = 0) -> Loadout {
            Loadout(bar: bar, perSide: plates.map { PlateCount(plate: $0, count: 1) }, collarLb: collar, preservesOrder: true)
        }
        let squat115 = load(.bar45lb, [lb(35)])
        let press100 = load(.bar45lb, [lb(25), lb(2.5)])
        let lb225 = load(.bar45lb, [lb(45)])
        let lb315 = load(.bar45lb, [lb(45), lb(45), lb(45)])
        let mixed = load(.bar45lb, [lb(45), lb(25), lb(10), lb(5), lb(2.5)])
        let kgs = load(.bar20kg, [kg(25), kg(20), kg(10), kg(2.5), kg(1.25)])
        let collared = load(.bar45lb, [lb(45), lb(25)], collar: 5)
        // The approved plate-loading mockup: 138.7 lb on a 45 lb bar.
        let mockup = load(.bar45lb, [kg(20), kg(1.25)])
        func item(_ name: String, _ loadout: Loadout, _ theme: PlateThemeID, _ shot: StudioShot,
                  style: PlateVisualStyle = .steel) -> Item {
            let (w, h): (Int, Int) = switch shot {
            case .row: (390, 84)
            case .hero: (390, 219)
            case .blowup: (390, 300)
            }
            return Item(name: name, request: .init(loadout: loadout, style: style, theme: theme, shot: shot,
                                                   width: w, height: h, scale: 3))
        }
        return [
            item("01-row-squat115-custom", squat115, .custom, .row),
            item("02-row-press100-custom", press100, .custom, .row),
            item("03-hero-225-lbColourBumpers", lb225, .lbColourBumpers, .hero),
            item("04-hero-squat115-custom", squat115, .custom, .hero),
            item("05-hero-mixed-lbBlackIron", mixed, .lbBlackIron, .hero),
            item("06-hero-kg-iwfCompetition", kgs, .iwfCompetition, .hero, style: .bumper),
            item("07-hero-315-ipfCalibrated", lb315, .ipfCalibrated, .hero),
            item("08-blowup-mixed-lbColourBumpers", mixed, .lbColourBumpers, .blowup),
            item("09-blowup-kg-iwfCompetition", kgs, .iwfCompetition, .blowup, style: .bumper),
            item("10-hero-collars-cadenceHouse", collared, .cadenceHouse, .hero),
            item("11-row-mixed-lbGreyHammertone", mixed, .lbGreyHammertone, .row),
            item("12-hero-mixed-blackBumpersBand", mixed, .blackBumpersBand, .hero),
            item("13-hero-mockup-custom", mockup, .custom, .hero, style: .bumper),
            item("14-blowup-mockup-custom", mockup, .custom, .blowup, style: .bumper),
            item("15-hero-kg-iwfTraining", kgs, .iwfTraining, .hero, style: .bumper),
        ]
    }
}

extension RenderLab {
    /// Check the production camera through SceneKit's projection, not a copy
    /// of the fit formula. The wide, short case reproduced #374's clipping;
    /// the taller case is the inspector's scaled Dynamic Type canvas.
    @MainActor
    static func checkFraming() async -> [String] {
        guard let studio = await StudioRenderer.shared.studio(loadout: framingLoadout, style: .bumper, theme: .lbColourBumpers)
        else { return ["studio build failed"] }
        studio.explode(1)
        var failures: [String] = []
        let cases: [(CGFloat, CGFloat, CGFloat)] = [(592, 300, 1), (1184, 300, 2), (1184, 600, 2)]
        for (width, height, scale) in cases {
            let captionHeight = UIFont.monospacedDigitSystemFont(ofSize: 14 * scale, weight: .semibold).lineHeight + 12
            studio.frame(.blowup, aspect: Double(width / height), captionFraction: Double(captionHeight / height))
            let view = SCNView(frame: CGRect(x: 0, y: 0, width: width, height: height))
            view.scene = studio.scene
            view.pointOfView = studio.cameraNode
            _ = view.snapshot() // establish SceneKit's actual viewport before projecting
            let viewport = CGRect(x: 0, y: 0, width: width, height: height - captionHeight)
            for entry in studio.nearDiscs {
                let (low, high) = entry.node.boundingBox
                let fits = (0..<8).allSatisfy { corner in
                    let local = SCNVector3(corner & 1 == 0 ? low.x : high.x,
                                          corner & 2 == 0 ? low.y : high.y,
                                          corner & 4 == 0 ? low.z : high.z)
                    let p = view.projectPoint(entry.node.convertPosition(local, to: nil))
                    return p.z > 0 && p.z < 1 && viewport.contains(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
                }
                if !fits { failures.append("\(Int(width))x\(Int(height)): plate \(entry.disc.index + 1) clips") }
            }
        }
        return failures
    }

    /// The gym environment alone around a mirror ball and a grey ball:
    /// proves the backdrop draws and the lighting environment reflects.
    static func environmentProbe() async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let device = MTLCreateSystemDefaultDevice() else { return continuation.resume(returning: nil) }
                let scene = SCNScene()
                scene.background.contents = StudioTextures.environment
                scene.lightingEnvironment.contents = StudioTextures.studioLight
                scene.lightingEnvironment.intensity = StudioLighting.environmentIntensity
                for (x, metal) in [(-260.0, 1.0), (260.0, 0.0)] {
                    let ball = SCNSphere(radius: 220)
                    ball.segmentCount = 96
                    ball.firstMaterial = StudioMaterials.pbr(UIColor(white: metal > 0 ? 0.95 : 0.6, alpha: 1),
                                                             metalness: metal, roughness: metal > 0 ? 0.02 : 0.6)
                    let node = SCNNode(geometry: ball)
                    node.position = SCNVector3(Float(x), 0, 0)
                    scene.rootNode.addChildNode(node)
                }
                let camera = SCNNode()
                camera.camera = SCNCamera()
                camera.camera?.zNear = 10
                camera.camera?.zFar = 50000
                camera.camera?.fieldOfView = 70
                camera.position = SCNVector3(0, 0, 1200)
                scene.rootNode.addChildNode(camera)
                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = scene
                renderer.pointOfView = camera
                continuation.resume(returning: renderer.snapshot(atTime: 0, with: CGSize(width: 1170, height: 660),
                                                                 antialiasingMode: .multisampling4X))
            }
        }
    }
}

struct RenderLabView: View {
    @State private var rendered: [(name: String, image: UIImage)] = []
    @State private var done = false
    @State private var failed: [String] = []

    var body: some View {
#if DEBUG
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if RenderLab.framingOnly {
                    BarbellInspectionView(solution: PlateSolution(loadout: RenderLab.framingLoadout,
                                                                  targetLb: RenderLab.framingLoadout.totalLb),
                                          plateStyle: .bumper, plateTheme: .lbColourBumpers)
                        .preferredColorScheme(.dark)
                }
                ForEach(rendered, id: \.name) { entry in
                    Text(entry.name).font(.caption.monospaced())
                    Image(uiImage: entry.image).resizable().scaledToFit()
                }
                if done {
                    // The UI test reads this label: a render that failed must fail the run.
                    Text(failed.isEmpty ? "render-lab-done" : "render-lab-failed: \(failed.joined(separator: ", "))")
                        .font(.caption).accessibilityIdentifier("render-lab-done")
                }
            }
            .padding()
        }
        .background(Color.black)
        .task { await run() }
#else
        EmptyView()
#endif
    }

    private func run() async {
        if RenderLab.framingOnly {
            failed = await RenderLab.checkFraming()
            done = true
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("render-lab", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Stored renders would let the lab show an earlier build's output.
        await StudioRenderer.shared.purge()
        var timings = ""
        let env = StudioTextures.environment
        timings += "environment \(Int(env.size.width))x\(Int(env.size.height)) cg=\(env.cgImage != nil)\n"
        if let diag = await RenderLab.environmentProbe() {
            try? diag.pngData()?.write(to: dir.appendingPathComponent("00-diag-environment.png"))
            rendered.append(("00-diag-environment", diag))
        }
        for item in RenderLab.matrix {
            let start = Date()
            guard let image = await StudioRenderer.shared.render(item.request) else {
                timings += "\(item.name) FAILED\n"
                failed.append(item.name)
                continue
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            try? image.pngData()?.write(to: dir.appendingPathComponent("\(item.name).png"))
            timings += "\(item.name) \(ms) ms\n"
            rendered.append((item.name, image))
        }
        try? timings.write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
        done = true
    }
}
