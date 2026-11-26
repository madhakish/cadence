import CadenceCore
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
        let lb225 = load(.bar45lb, [lb(45), lb(45)])
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
            item("01-row-squat\(Weight.trim(squat115.totalLb))-custom", squat115, .custom, .row),
            item("02-row-press\(Weight.trim(press100.totalLb))-custom", press100, .custom, .row),
            item("03-hero-\(Weight.trim(lb225.totalLb))-lbColourBumpers", lb225, .lbColourBumpers, .hero),
            item("04-hero-squat\(Weight.trim(squat115.totalLb))-custom", squat115, .custom, .hero),
            item("05-hero-mixed-lbBlackIron", mixed, .lbBlackIron, .hero),
            item("06-hero-kg-iwfCompetition", kgs, .iwfCompetition, .hero, style: .bumper),
            item("07-hero-\(Weight.trim(lb315.totalLb))-ipfCalibrated", lb315, .ipfCalibrated, .hero),
            item("08-blowup-mixed-lbColourBumpers", mixed, .lbColourBumpers, .blowup),
            item("09-blowup-kg-iwfCompetition", kgs, .iwfCompetition, .blowup, style: .bumper),
            item("10-hero-collars-cadenceHouse", collared, .cadenceHouse, .hero),
            item("11-row-mixed-lbGreyHammertone", mixed, .lbGreyHammertone, .row),
            item("12-hero-mixed-blackBumpersBand", mixed, .blackBumpersBand, .hero),
            item("13-hero-mockup-custom", mockup, .custom, .hero, style: .bumper),
            item("14-blowup-mockup-custom", mockup, .custom, .blowup, style: .bumper),
            item("15-hero-kg-iwfTraining", kgs, .iwfTraining, .hero, style: .bumper),
            item("16-hero-machined-steel", mixed, .lbMachinedSteel, .hero),
            item("17-blowup-calibrated-gloss", kgs, .ipfCalibratedGloss, .blowup),
            item("18-hero-empty-bar", load(.bar20kg, []), .custom, .hero),
            item("19-blowup-fractional", load(.bar20kg, [kg(5), kg(0.625)]), .custom, .blowup),
            item("20-hero-long-stack", framingLoadout, .lbColourBumpers, .hero),
            item("21-hero-135-lbColourBumpers", load(.bar45lb, [lb(45)]), .lbColourBumpers, .hero),
        ]
    }
}

extension RenderLab {
    /// Inspect the same projected rectangles that the compositor draws.
    static func checkFraming() async -> [String] {
        var failures: [String] = []
        let cases: [(CGFloat, CGFloat, CGFloat)] = [(592, 300, 1), (1184, 300, 2), (1184, 600, 2)]
        for (width, height, scale) in cases {
            let captionSize = 14 * scale
            let captionHeight = UIFont.monospacedDigitSystemFont(ofSize: captionSize, weight: .semibold).lineHeight + 12
            let scene = PhotographicBar(loadout: framingLoadout, style: .bumper, theme: .lbColourBumpers,
                                        size: CGSize(width: width, height: height), shot: .blowup,
                                        progress: 1, captionSize: captionSize)
            let viewport = CGRect(x: 0, y: 0, width: width, height: height - captionHeight)
            for item in scene.projectedPlates where item.disc.side < 0 && !viewport.contains(item.bounds) {
                failures.append("\(Int(width))x\(Int(height)): plate \(item.disc.index + 1) clips at \(item.bounds)")
            }
        }
        return failures
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("studio-framing-proof.txt")
            try? (failed.isEmpty ? "PASS" : failed.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
            done = true
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("render-lab", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Stored renders would let the lab show an earlier build's output.
        await StudioRenderer.shared.purge()
        var timings = ""
        // An asset-catalog omission would otherwise take the renderer's
        // recovery path and still yield a perfectly valid PNG.
        for name in PhotoEquipment.stageNames + PhotoEquipment.componentNames {
            if UIImage(named: name)?.cgImage == nil { failed.append("missing " + name) }
        }
        if let diag = UIImage(named: PhotoEquipment.stage(.custom)) {
            timings += "environment \(Int(diag.size.width))x\(Int(diag.size.height))\n"
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
        for failure in failed { timings += "FAILED " + failure + "\n" }
        try? timings.write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
        done = true
    }
}
