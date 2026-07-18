import SwiftUI
import SwiftData

/// The membership tag, without the keychain. Shows the stored barcode photo
/// at max brightness so the front-desk scanner reads it off the screen.
/// One gym can't issue two tags; the phone is the second tag.
struct GymCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var gyms: [Gym]

    let gym: Gym?
    @State private var selectedGymName: String?
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled

    private var current: Gym? {
        if let selectedGymName {
            return gyms.first { $0.name == selectedGymName }
        }
        return gym ?? gyms.first { $0.isDefault } ?? gyms.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if gyms.count > 1 {
                    Picker("Gym", selection: Binding(
                        get: { current?.name ?? "" },
                        set: { selectedGymName = $0 }
                    )) {
                        ForEach(gyms) { Text($0.name).tag($0.name) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                if let data = current?.barcodeImageData, let image = UIImage(data: data) {
                    Spacer()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Text(current?.barcodeLabel ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No tag stored",
                        systemImage: "barcode",
                        description: Text("Settings → Gyms → add a photo of your barcode.")
                    )
                }
            }
            // White background helps laser scanners; the barcode area stays white.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(current?.name ?? "Gym tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIScreen.main.brightness = 1.0
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
    }
}
