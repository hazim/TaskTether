//
//  SparklineView.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - SparklineView
// A 7-day ECG-style productivity sparkline.
// Matches the HTML preview exactly — area fill, polyline, data points, day labels.
//
// - The rightmost point is always today
// - Today's dot is larger and full opacity
// - Today's day label is highlighted in the accent colour
// - Horizontal grid lines at 25%, 50%, 75%
// - All colours come from the active theme's sparkline token
//
// Usage:
//   SparklineView(scores: [48, 55, 62, 58, 70, 62, 74])
//   SparklineView(scores: Array(repeating: 0, count: 7)) ← placeholder

struct SparklineView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    // 7 values, oldest first, today last (index 6)
    let scores: [Double]

    // Padding inside the drawing canvas
    private let pad: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // ECG line drawn using Canvas
            Canvas { context, size in
                let n      = scores.count
                guard n > 1 else { return }

                let w      = size.width
                let h      = size.height
                let minVal = scores.min() ?? 0
                let maxVal = scores.max() ?? 1
                let range  = maxVal - minVal == 0 ? 1.0 : maxVal - minVal

                // X and Y positions for each data point
                let xs: [CGFloat] = (0..<n).map { i in
                    pad + CGFloat(i) / CGFloat(n - 1) * (w - pad * 2)
                }
                let ys: [CGFloat] = scores.map { v in
                    h - pad - CGFloat((v - minVal) / range) * (h - pad * 2)
                }

                let color = themeManager.sparkline

                // Grid lines at 25%, 50%, 75%
                for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
                    let gy = pad + (1 - fraction) * (h - pad * 2)
                    var gridLine = Path()
                    gridLine.move(to: CGPoint(x: pad, y: gy))
                    gridLine.addLine(to: CGPoint(x: w - pad, y: gy))
                    context.stroke(
                        gridLine,
                        with: .color(color.opacity(0.10)),
                        lineWidth: 0.5
                    )
                }

                // Area fill — polygon from bottom-left to points to bottom-right
                var area = Path()
                area.move(to: CGPoint(x: xs[0], y: h - pad))
                for i in 0..<n {
                    area.addLine(to: CGPoint(x: xs[i], y: ys[i]))
                }
                area.addLine(to: CGPoint(x: xs[n - 1], y: h - pad))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.07)))

                // Line — connects all data points
                var line = Path()
                line.move(to: CGPoint(x: xs[0], y: ys[0]))
                for i in 1..<n {
                    line.addLine(to: CGPoint(x: xs[i], y: ys[i]))
                }
                context.stroke(
                    line,
                    with: .color(color.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )

                // Data point circles — today (last) is larger and full opacity
                for i in 0..<n {
                    let isToday = i == n - 1
                    let radius: CGFloat = isToday ? 3.2 : 2.2
                    let opacity: CGFloat = isToday ? 1.0 : 0.5
                    let rect = CGRect(
                        x: xs[i] - radius,
                        y: ys[i] - radius,
                        width:  radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
            .frame(
                width:  DesignTokens.sparklineWidth,
                height: DesignTokens.sparklineHeight
            )

            // Day labels — S M T W T F S, rolling from today
            HStack(spacing: 0) {
                ForEach(Array(dayLabels().enumerated()), id: \.offset) { index, label in
                    let isToday = index == 6
                    Text(label)
                        .font(.system(size: 8, weight: isToday ? .medium : .regular))
                        .foregroundStyle(
                            isToday
                                ? themeManager.sparkline.opacity(0.9)
                                : themeManager.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: DesignTokens.sparklineWidth)
        }
    }

    // MARK: - Day Labels
    // Builds a 7-element array of single-character day labels (S/M/T/W/T/F/S),
    // rolling backwards from today so the rightmost label is always today.

    private func dayLabels() -> [String] {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let today   = Calendar.current.component(.weekday, from: Date()) - 1 // 0 = Sunday
        return (0..<7).map { offset in
            let index = (today - (6 - offset) + 7) % 7
            return letters[index]
        }
    }
}

// MARK: - Preview
#Preview {
    SparklineView(scores: [48, 55, 62, 58, 70, 62, 74])
        .padding(DesignTokens.paddingMd)
        .environmentObject(ThemeManager())
}
