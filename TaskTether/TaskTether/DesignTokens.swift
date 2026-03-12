//
//  DesignTokens.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - DesignTokens
// A single place for every spacing, sizing, and corner radius value used in the app.
// Nothing in any view file should contain a raw number for layout purposes.
// Instead of writing .padding(16), write .padding(DesignTokens.paddingMd)
// This makes it trivial to adjust the entire app's spacing in one place.

enum DesignTokens {

    // MARK: - Popover Width
    // The menu bar popover has fixed widths depending on which panel is shown.

    /// Width of the compact and expanded views.
    static let popoverWidth:      CGFloat = 300

    /// Width of the full panel when the Today view is open (popover + task list side by side).
    static let popoverWidthToday: CGFloat = 600

    // MARK: - Padding
    // Used for internal padding inside containers and components.

    /// Extra small padding — used for tight inner elements, e.g. icon buttons.
    static let paddingXs: CGFloat = 4

    /// Small padding — used for compact rows and secondary elements.
    static let paddingSm: CGFloat = 8

    /// Medium padding — the standard padding for most panels and sections.
    static let paddingMd: CGFloat = 16

    /// Large padding — used for prominent sections or the connect screen.
    static let paddingLg: CGFloat = 24

    // MARK: - Spacing
    // Used for gaps between elements inside stacks (HStack/VStack spacing:).

    /// Extra small spacing — tight icon/label pairs.
    static let spacingXs: CGFloat = 4

    /// Small spacing — between rows and related elements.
    static let spacingSm: CGFloat = 8

    /// Medium spacing — between distinct sections within a panel.
    static let spacingMd: CGFloat = 14

    /// Large spacing — between major layout blocks.
    static let spacingLg: CGFloat = 20

    // MARK: - Corner Radius
    // Used for rounded rectangles, buttons, cards, and the popover background.

    /// Small radius — subtle rounding on rows and chips.
    static let radiusSm: CGFloat = 4

    /// Medium radius — standard buttons and cards.
    static let radiusMd: CGFloat = 8

    /// Large radius — popover window, settings panel, modal surfaces.
    static let radiusLg: CGFloat = 12

    /// Extra large radius — pill-shaped controls like the segmented nav.
    static let radiusXl: CGFloat = 20

    // MARK: - Icon Size
    // SF Symbol sizes used consistently across the app.

    /// Small icon — footer bar icons (gear, exit).
    static let iconSm: CGFloat = 13

    /// Medium icon — inline icons next to button labels.
    static let iconMd: CGFloat = 15

    /// Large icon — standalone icons in empty states or onboarding.
    static let iconLg: CGFloat = 24

    // MARK: - Font Sizes
    // Used with .font(.system(size:)) throughout all views.

    /// Caption — timestamps, tertiary labels.
    static let fontCaption:    CGFloat = 11

    /// Small — secondary labels, status text.
    static let fontSm:         CGFloat = 12

    /// Body — standard readable text, button labels.
    static let fontBody:       CGFloat = 13

    /// Medium — section headers, view titles.
    static let fontMd:         CGFloat = 14

    /// Large — the productivity score percentage number.
    static let fontScoreLabel: CGFloat = 36

    // MARK: - Status Dot Sizes
    // The three-layer glow dot used for Reminders and Google Tasks status.

    /// Outer glow ring diameter.
    static let dotOuter:  CGFloat = 20

    /// Mid glow ring diameter.
    static let dotMid:    CGFloat = 13

    /// Core solid dot diameter.
    static let dotCore:   CGFloat = 7

    // MARK: - Sparkline
    // Dimensions for the 7-day ECG sparkline in the expanded view.

    static let sparklineWidth:  CGFloat = 120
    static let sparklineHeight: CGFloat = 32

    // MARK: - Animation
    // Shared durations for transitions and interactive animations.

    /// Fast — hover states, checkbox ticks, immediate feedback.
    static let animFast:   Double = 0.14

    /// Standard — panel transitions, theme switches.
    static let animNormal: Double = 0.25

    /// Slow — Today panel slide-in/out.
    static let animSlow:   Double = 0.30
}
