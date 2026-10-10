import SwiftUI

enum RahoTheme {
    static let midnight = Color(red: 0.035, green: 0.063, blue: 0.075)
    static let surface = Color(red: 0.078, green: 0.110, blue: 0.122)
    static let raised = Color(red: 0.110, green: 0.145, blue: 0.153)
    static let amber = Color(red: 1, green: 0.733, blue: 0.345)
    static let mint = Color(red: 0.580, green: 0.882, blue: 0.765)
    static let red = Color(red: 1, green: 0.376, blue: 0.345)
    static let text = Color(red: 0.949, green: 0.961, blue: 0.933)
    static let muted = Color(red: 0.639, green: 0.702, blue: 0.710)
    static let border = Color.white.opacity(0.085)
}

struct RahoCard<Content: View>: View {
    var accent: Color = RahoTheme.border
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RahoTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(accent, lineWidth: 1))
    }
}

struct RahoPrimaryButton: ButtonStyle {
    var color: Color = RahoTheme.amber
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(RahoTheme.midnight)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct RahoSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(RahoTheme.text)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RahoTheme.raised.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RahoTheme.border))
    }
}

struct StatusPill: View {
    let title: String
    var symbol: String = "circle.fill"
    var color: Color = RahoTheme.mint

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .rounded).weight(.bold))
            .tracking(1.7)
            .foregroundStyle(RahoTheme.muted)
    }
}

struct NoticeView: View {
    let message: String
    var symbol: String = "exclamationmark.triangle.fill"
    var color: Color = RahoTheme.amber
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).padding(.top, 2)
            Text(message).font(.footnote).foregroundStyle(RahoTheme.text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct LanguageSelector: View {
    @Binding var language: VoiceLanguage
    var body: some View {
        HStack(spacing: 8) {
            ForEach(VoiceLanguage.allCases) { item in
                Button { language = item } label: {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(language == item ? RahoTheme.midnight : RahoTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(language == item ? RahoTheme.amber : RahoTheme.raised,
                                    in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(language == item ? [.isSelected] : [])
            }
        }
    }
}

struct RoadIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Circle().fill(RahoTheme.amber.opacity(0.06)).frame(width: 160, height: 160).offset(x: size.width * 0.28, y: -20)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 50, weight: .light)).foregroundStyle(RahoTheme.amber)
                    .offset(x: size.width * 0.28, y: -28)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.12, y: size.height))
                    path.addCurve(to: CGPoint(x: size.width * 0.72, y: 8),
                                  control1: CGPoint(x: size.width * 0.35, y: size.height * 0.25),
                                  control2: CGPoint(x: size.width * 0.6, y: size.height * 1.05))
                }
                .stroke(RahoTheme.mint.opacity(0.13), style: StrokeStyle(lineWidth: 46, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.12, y: size.height))
                    path.addCurve(to: CGPoint(x: size.width * 0.72, y: 8),
                                  control1: CGPoint(x: size.width * 0.35, y: size.height * 0.25),
                                  control2: CGPoint(x: size.width * 0.6, y: size.height * 1.05))
                }
                .stroke(RahoTheme.mint.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 10]))
            }
        }
        .frame(height: 130)
        .clipped()
        .accessibilityHidden(true)
    }
}
