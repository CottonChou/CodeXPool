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

struct CollapseChevronButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.frostedCapsule(prominent: true, density: .compact))
    }
}

struct CardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    }
                }
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
    func cardSurface(cornerRadius: CGFloat = LayoutRules.cardRadius, tint: Color? = nil) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func frostedCapsuleInput() -> some View {
        modifier(FrostedCapsuleInputModifier())
    }
}

struct FrostedCapsuleButtonStyle: ButtonStyle {
    enum Density {
        case regular
        case compact
    }

    let prominent: Bool
    let tint: Color?
    let density: Density

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minimumHeight)
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

    private var font: Font {
        switch density {
        case .regular:
            return .subheadline.weight(prominent ? .semibold : .medium)
        case .compact:
            return .callout.weight(prominent ? .semibold : .medium)
        }
    }

    private var horizontalPadding: CGFloat {
        density == .compact ? 10 : 12
    }

    private var verticalPadding: CGFloat {
        density == .compact ? 5 : 7
    }

    private var minimumHeight: CGFloat {
        density == .compact ? 30 : 34
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
    static func frostedCapsule(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular
    ) -> Self {
        FrostedCapsuleButtonStyle(prominent: prominent, tint: tint, density: density)
    }
}

private struct FrostedCapsuleInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(separatorColor, lineWidth: 1)
            }
    }

    private var separatorColor: Color {
        #if canImport(AppKit)
        Color(nsColor: .separatorColor)
        #else
        Color.secondary.opacity(0.2)
        #endif
    }
}
