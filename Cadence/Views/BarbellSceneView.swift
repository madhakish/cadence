import CadenceCore
import SceneKit
import SwiftUI
import UIKit

/// The live inspector: the studio scene in a view. Assembled shows the whole
/// loaded bar on the platform; a tap slides the near sleeve's plates out so
/// every face reads, with a caption under each.
struct BarbellSceneView: UIViewRepresentable {
    let loadout: Loadout
    let plateStyle: PlateVisualStyle
    var plateTheme: PlateThemeID = .custom
    let exploded: Bool
    let reduceMotion: Bool

    static var isSupported: Bool { StudioRenderer.isSupported }

    func makeUIView(context: Context) -> FittingSceneView {
        let view = FittingSceneView(frame: .zero)
        view.antialiasingMode = .multisampling4X
        view.isJitteringEnabled = true
        view.rendersContinuously = false
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isAccessibilityElement = false
        view.backgroundColor = UIColor(Theme.sceneStudio)
        view.scene = context.coordinator.studio.scene
        context.coordinator.attach(view)
        context.coordinator.apply(exploded: exploded, animated: false, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ view: FittingSceneView, context: Context) {
        context.coordinator.apply(exploded: exploded, animated: true, reduceMotion: reduceMotion)
    }

    func makeCoordinator() -> StudioInspector { StudioInspector(loadout: loadout, style: plateStyle, theme: plateTheme) }

    final class FittingSceneView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(bounds.size)
        }
    }
}

/// Denominations are equipment identities, not rounded workout totals. Keep
/// custom values such as 0.625 kg intact on the disc and its readable caption.
func inspectionPlateValue(_ plate: Plate) -> String {
    let value = String(plate.value)
    return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
}

func inspectionPlateLabel(_ plate: Plate) -> String {
    "\(inspectionPlateValue(plate)) \(plate.unit.rawValue)"
}

@MainActor
final class StudioInspector {
    let studio: BarbellStudio
    private var captions: [UILabel] = []
    private var explodedNow: Bool?
    private var transition = 0
    private var transitioning = false
    private var viewSize = CGSize(width: 390, height: 300)
    private weak var view: SCNView?

    init(loadout: Loadout, style: PlateVisualStyle, theme: PlateThemeID) {
        studio = BarbellStudio(loadout: loadout, style: style, theme: theme)
        captions = studio.nearDiscs.map { entry in
            let caption = UILabel()
            caption.text = inspectionPlateLabel(entry.disc.plate)
            caption.textColor = UIColor(white: 0.96, alpha: 1)
            caption.backgroundColor = UIColor(Theme.sceneStudio).withAlphaComponent(0.9)
            caption.textAlignment = .center
            caption.layer.cornerRadius = 5
            caption.layer.masksToBounds = true
            caption.isUserInteractionEnabled = false
            caption.isAccessibilityElement = false
            caption.isHidden = true
            return caption
        }
    }

    func attach(_ view: BarbellSceneView.FittingSceneView) {
        self.view = view
        view.pointOfView = studio.cameraNode
        for caption in captions { view.addSubview(caption) }
        view.onLayout = { [weak self] size in
            guard let self, size != self.viewSize, size.width > 0, size.height > 0 else { return }
            self.viewSize = size
            self.studio.frame(self.explodedNow == true ? .blowup : .hero, aspect: Double(size.width / size.height))
            self.updateCaptions()
        }
    }

    func apply(exploded: Bool, animated: Bool, reduceMotion: Bool) {
        guard exploded != explodedNow else { updateCaptions(); return }
        explodedNow = exploded
        transition += 1
        let current = transition
        let duration = animated && !reduceMotion ? 0.32 : 0
        transitioning = duration > 0
        for caption in captions { caption.isHidden = true }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in
                guard let self, self.transition == current else { return }
                self.transitioning = false
                self.updateCaptions()
            }
        }
        studio.explode(exploded ? 1 : 0)
        studio.frame(exploded ? .blowup : .hero, aspect: Double(viewSize.width / max(1, viewSize.height)))
        SCNTransaction.commit()
        if duration == 0 { updateCaptions() }
    }

    /// Screen-space text never shrinks with the model. Each physical disc,
    /// including duplicates, owns a caption directly below its projected face.
    private func updateCaptions() {
        guard let view else { return }
        for (caption, entry) in zip(captions, studio.nearDiscs) {
            caption.isHidden = explodedNow != true || transitioning
            guard !caption.isHidden else { continue }
            caption.font = UIFontMetrics(forTextStyle: .subheadline)
                .scaledFont(for: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold))
            caption.sizeToFit()
            let below = SCNVector3(entry.node.position.x, Float(-entry.disc.radius - 30), 0)
            let point = view.projectPoint(below)
            let width = caption.bounds.width + 14, height = caption.bounds.height + 8
            let x = max(4, min(viewSize.width - width - 4, CGFloat(point.x) - width / 2))
            caption.frame = CGRect(x: x, y: min(viewSize.height - height - 4, CGFloat(point.y)), width: width, height: height)
        }
    }
}
