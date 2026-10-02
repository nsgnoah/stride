import SwiftUI

extension View {
    /// The dark card each tab leads with: deep ink with a glow in one corner, like the icon.
    /// Meant for a List row; it takes over the row's background and insets.
    func inkCard(glow: Color) -> some View {
        self
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [.ink, .inkDeep], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [glow.opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08)) }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

/// A small label over a value, as used on the ink cards.
struct CardStat: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

/// The eyebrow line at the top of an ink card.
struct CardEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.stride)
    }
}
