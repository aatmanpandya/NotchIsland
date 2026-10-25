import SwiftUI

struct ClockPanel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 36, weight: .light, design: .rounded).monospacedDigit())
                Text(context.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                WeekStrip(date: context.date)
            }
        }
    }
}

private struct WeekStrip: View {
    let date: Date

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                let isToday = calendar.isDate(day, inSameDayAs: date)
                VStack(spacing: 3) {
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(day, format: .dateTime.day())
                        .font(.system(size: 11, weight: isToday ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(isToday ? .black : .secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(isToday ? Color.white : .clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct BatteryIndicator: View {
    @ObservedObject var battery: BatteryService

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 6) {
                Text("\(battery.level)%").monospacedDigit()
                BatteryGlyph(level: battery.level, isCharging: battery.isPluggedIn)
            }
        }
    }
}

private struct BatteryGlyph: View {
    let level: Int
    let isCharging: Bool

    private var fill: Color { isCharging ? .green : level <= 20 ? .red : .white }

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
