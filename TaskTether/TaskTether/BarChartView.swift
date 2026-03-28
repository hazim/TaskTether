//
//  BarChartView.swift
//  TaskTether
//
//  Created: 28/03/2026
//

import SwiftUI

// MARK: - BarChartView
// Displays 7 days of completion data as vertical bars.
//
// Bar states:
//   nil  → empty slot (no data — day had no tracked tasks)
//   0    → minimum-height bar in muted colour (had tasks, completed none)
//   1-100 → proportional bar
//
// Today's bar uses the theme accent colour.
// Past bars use the accent at reduced opacity.

struct BarChartView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    // 7 values oldest→newest, today last. nil = no data.
    let percentages: [Int?]

    // Day labels — "M", "T", "W" etc. derived internally.
    private var dayLabels: [String] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset - 6, to: today)!
            let fmt  = DateFormatter()
            fmt.dateFormat = "EEEEE"  // Single letter: M, T, W…
            return fmt.string(from: date).uppercased()
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let pct      = percentages.count > i ? percentages[i] : nil
                let isToday  = i == 6

                VStack(spacing: 4) {
                    // Bar area — fixed height so labels always have room
                    ZStack(alignment: .bottom) {
                        // Track (empty background)
                        Color.clear.frame(height: 36)

                        if let pct {
                            // Minimum 3pt so 0% days are distinguishable from no data
                            let barHeight = max(3, 36 * CGFloat(pct) / 100)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isToday
                                      ? themeManager.accent
                                      : themeManager.accent.opacity(0.35))
                                .frame(height: barHeight)
                        }
                        // nil → no bar, slot stays empty
                    }

                    // Day label — always below bar area
                    Text(dayLabels[i])
                        .font(.system(size: 8, weight: isToday ? .semibold : .regular,
                                      design: .monospaced))
                        .foregroundStyle(isToday
                                         ? themeManager.accent
                                         : themeManager.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Preview

#Preview("Mixed data") {
    BarChartView(percentages: [100, nil, 0, 60, nil, 45, 75])
        .frame(width: 260, height: 60)
        .padding()
        .environmentObject(ThemeManager())
}

#Preview("No data yet") {
    BarChartView(percentages: [nil, nil, nil, nil, nil, nil, 50])
        .frame(width: 260, height: 60)
        .padding()
        .environmentObject(ThemeManager())
}
