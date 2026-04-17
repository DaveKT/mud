import SwiftUI
import MudConfiguration

struct LightingPreviewCard: View {
    let lighting: Lighting
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(lighting.previewImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                Text(lighting.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Lighting {
    var previewImageName: String {
        switch self {
        case .auto: return "LightingPreviewSystem"
        case .bright: return "LightingPreviewBright"
        case .dark: return "LightingPreviewDark"
        }
    }

    var displayName: String {
        switch self {
        case .auto: return "System"
        case .bright: return "Bright"
        case .dark: return "Dark"
        }
    }
}
