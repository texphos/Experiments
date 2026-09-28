import SwiftUI
import UIKit
import HearthdayCore

/// Hearthday's palette: warm flour and crust for the day, indigo for the hours you're asleep.
enum Palette {
    static let flour = dynamic(light: 0xF7F1E8, dark: 0x1B1612)
    static let crumb = dynamic(light: 0xFFFBF5, dark: 0x282119)
    static let crust = dynamic(light: 0x9A4A1F, dark: 0xE38C52)
    static let ember = dynamic(light: 0xD9601F, dark: 0xF08A4B)
    static let rye = dynamic(light: 0x2A201A, dark: 0xF3EBE1)
    static let ash = dynamic(light: 0x6F6259, dark: 0xB9AC9F)
    static let hairline = dynamic(light: 0xE6DCCF, dark: 0x3A3027)
    static let night = dynamic(light: 0x3E4577, dark: 0x8C95D6)
    static let sage = dynamic(light: 0x5E7050, dark: 0xA7BB94)
    static let plum = dynamic(light: 0x7D5A80, dark: 0xC7A3CA)
    static let warning = dynamic(light: 0xB5480F, dark: 0xFFA36B)

    static func busy(_ kind: BusyBlock.Kind) -> Color {
        switch kind {
        case .sleep: return night
        case .work: return sage
        case .other: return plum
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Typo {
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font { .system(style, design: .serif).weight(.semibold) }
    static func heading(_ style: Font.TextStyle = .title3) -> Font { .system(style, design: .serif).weight(.semibold) }
    static func clock(_ style: Font.TextStyle = .title) -> Font { .system(style, design: .rounded).weight(.semibold).monospacedDigit() }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.crumb, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.crust.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.crust)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.crust.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
    }
}

struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Palette.crust

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.1), in: Capsule())
    }
}

/// Diagonal hatching so busy time is distinguishable without relying on color.
struct Hatching: View {
    var color: Color
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 6
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1.2)
        }
        .background(color.opacity(0.14))
    }
}

/// Shared empty/error state layout.
struct StateMessage: View {
    var systemImage: String
    var title: String
    var message: String
    var tint: Color = Palette.crust

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(Typo.heading()).multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(Palette.ash)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}
