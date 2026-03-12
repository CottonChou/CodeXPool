import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .cardSurface(cornerRadius: LayoutRules.cardRadius)
    }
}

struct CardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )
    }

    private var separatorColor: Color {
        #if canImport(AppKit)
        Color(nsColor: .separatorColor)
        #else
        Color.secondary.opacity(0.2)
        #endif
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = LayoutRules.cardRadius) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius))
    }
}

struct FrostedCapsuleButtonStyle: ButtonStyle {
    let prominent: Bool
    let tint: Color?

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(prominent ? .semibold : .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    Capsule()
                        .fill(prominent ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                    if prominent {
                        Capsule()
                            .fill(effectiveTint.opacity(0.14))
                    }
                }
            }
            .overlay {
                Capsule()
                    .stroke(separatorColor, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var separatorColor: Color {
        #if canImport(AppKit)
        let base = Color(nsColor: .separatorColor)
        #else
        let base = Color.secondary.opacity(0.2)
        #endif
        return prominent ? base.opacity(0.85) : base
    }

    private var effectiveTint: Color {
        tint ?? .accentColor
    }
}

extension ButtonStyle where Self == FrostedCapsuleButtonStyle {
    static func frostedCapsule(prominent: Bool = false, tint: Color? = nil) -> Self {
        FrostedCapsuleButtonStyle(prominent: prominent, tint: tint)
    }
}
