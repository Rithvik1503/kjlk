import SwiftUI

/// The window picker: a bordered capsule with the selected segment filled white.
struct RangeTogglePill: View {
    @Binding var selection: TrendWindow

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrendWindow.allCases) { window in
                let isSelected = window == selection

                Text(window.title)
                    .font(.auraMono(10.5))
                    .tracking(1.4)
                    .foregroundStyle(isSelected ? Color.black : Color.auraDimText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.white)
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard !isSelected else { return }
                        withAnimation(.easeInOut(duration: 0.18)) { selection = window }
                    }
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

#Preview("Toggle") {
    @Previewable @State var window: TrendWindow = .week

    RangeTogglePill(selection: $window)
        .padding(20)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
