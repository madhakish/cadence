import CadenceCore
import SwiftUI

/// The live inspector and fixed render-lab captures use the same draw pass.
struct BarbellSceneView: View, Animatable {
    let loadout: Loadout
    let plateStyle: PlateVisualStyle
    let plateTheme: PlateThemeID
    var progress: CGFloat
    @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 14

    init(loadout: Loadout, plateStyle: PlateVisualStyle, plateTheme: PlateThemeID, exploded: Bool, reduceMotion: Bool) {
        self.loadout = loadout
        self.plateStyle = plateStyle
        self.plateTheme = plateTheme
        progress = exploded ? 1 : 0
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { graphics, size in
            graphics.withCGContext { context in
                let scene = PhotographicBar(loadout: loadout, style: plateStyle, theme: plateTheme,
                                            size: size, shot: .hero, progress: progress, captionSize: captionSize)
                UIGraphicsPushContext(context)
                scene.draw(in: context)
                UIGraphicsPopContext()
            }
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
