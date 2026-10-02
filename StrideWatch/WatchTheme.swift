import SwiftUI

extension View {
    /// The icon's glow in one corner of the screen, in whatever colour suits the moment.
    func glow(_ color: Color) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity).background {
            RadialGradient(colors: [color.opacity(0.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 190)
                .ignoresSafeArea()
        }
    }

    /// The dark card used on the phone, sized for the wrist.
    func inkCard(glow: Color) -> some View {
        self
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [.ink, .inkDeep], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [glow.opacity(0.5), .clear], center: .topTrailing, startRadius: 0, endRadius: 150)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1)) }
    }
}

/// A small capitalised label, as on the phone's cards.
struct Eyebrow: View {
    let text: String
    var symbol: String?
    var color: Color = .ember

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text.uppercased()).tracking(0.6).lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(color)
    }
}

/// A label over a value.
struct WatchStat: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
        }
    }
}
