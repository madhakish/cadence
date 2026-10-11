import CadenceCore
import Metal
import SceneKit
import SwiftUI
import UIKit

/// DEBUG-only visual QA for the barbell studio: renders a fixed matrix of
/// loadouts × themes × shots with the production renderer, writes each PNG
/// to tmp/render-lab for the capture workflow, and shows them. Launched by
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
        ]
    }
}

extension RenderLab {
    /// The gym environment alone around a mirror ball and a grey ball:
    /// proves the backdrop draws and the lighting environment reflects.
    static func environmentProbe() async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let device = MTLCreateSystemDefaultDevice() else { return continuation.resume(returning: nil) }
                let scene = SCNScene()
                scene.background.contents = StudioTextures.environment
                scene.lightingEnvironment.contents = StudioTextures.environment
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

    var body: some View {
#if DEBUG
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rendered, id: \.name) { entry in
                    Text(entry.name).font(.caption.monospaced())
                    Image(uiImage: entry.image).resizable().scaledToFit()
                }
                if done {
                    Text("render-lab-done").font(.caption).accessibilityIdentifier("render-lab-done")
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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("render-lab", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var timings = ""
        let env = StudioTextures.environment
        timings += "environment \(Int(env.size.width))x\(Int(env.size.height)) cg=\(env.cgImage != nil)\n"
        if let diag = await RenderLab.environmentProbe() {
            try? diag.pngData()?.write(to: dir.appendingPathComponent("00-diag-environment.png"))
            rendered.append(("00-diag-environment", diag))
        }
        for item in RenderLab.matrix {
            let start = Date()
            guard let image = await StudioRenderer.shared.render(item.request) else { continue }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            try? image.pngData()?.write(to: dir.appendingPathComponent("\(item.name).png"))
            timings += "\(item.name) \(ms) ms\n"
            rendered.append((item.name, image))
        }
        try? timings.write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
        done = true
    }
}
