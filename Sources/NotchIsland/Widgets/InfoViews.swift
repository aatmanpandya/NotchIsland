import SwiftUI

struct BatteryIndicator: View {
    @ObservedObject var battery: BatteryService

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 6) {
                Text("\(battery.level)%").monospacedDigit()
                BatteryGlyph(level: battery.level, isCharging: battery.isPluggedIn,
                             isLowPower: battery.isLowPowerMode)
            }
        }
    }
}

private struct BatteryGlyph: View {
    let level: Int
    let isCharging: Bool
    let isLowPower: Bool

    private var fill: Color {
        if isCharging { return .green }
        if isLowPower { return .yellow }
        return level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).stroke(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill)
                    .frame(width: max(2, 21 * CGFloat(level) / 100))
                    .padding(2)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 25, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
    }
}
