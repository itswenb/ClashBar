import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

private struct FolderTabShape: Shape {
    // Keep the bottom edge open to join the content area. / 底边留空，与内容区相接。
    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: T.stroke / 2, dy: T.stroke / 2)
        let radius = min(T.cornerRadius, bounds.width / 2, bounds.height)
        var path = Path()
        path.move(to: CGPoint(x: bounds.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + radius, y: bounds.minY),
            control: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + radius),
            control: CGPoint(x: bounds.maxX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: rect.maxY))
        return path
    }
}

extension MenuBarRootView {
    private struct SegmentedControlStyle {
        let isMode: Bool

        static let mode = SegmentedControlStyle(isMode: true)
        static let tab = SegmentedControlStyle(isMode: false)

        var selectionBackgroundID: String {
            self.isMode ? "mode-segmented-selection-background" : "tab-segmented-selection-background"
        }

        var cornerRadius: CGFloat {
            self.isMode ? 10 : T.cornerRadius
        }

        var rowHeight: CGFloat {
            self.isMode ? 32 : 28
        }

        func selectedFillOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.10 : 0.045) : (isDark ? 0.22 : 0.12)
        }

        func selectedBorderOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.14 : 0.08) : (isDark ? 0.20 : 0.14)
        }

        func hoverFillOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.06 : 0.035) : 0
        }

        func selectedForegroundOpacity(isDark: Bool) -> CGFloat {
            self.isMode ? (isDark ? 0.96 : 0.88) : (isDark ? 0.96 : 0.92)
        }
    }

    var modeAndTabSection: some View {
        VStack(spacing: T.space2) {
            self.modeSwitcher
            self.topTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var modeSwitcher: some View {
        HStack(spacing: T.space2) {
            self.modeSegmentButton(
                title: tr("ui.mode.rule"),
                mode: .rule, symbol: "shield.lefthalf.filled")
            self.modeSegmentButton(
                title: tr("ui.mode.global"),
                mode: .global, symbol: "globe")
            self.modeSegmentButton(
                title: tr("ui.mode.direct"),
                mode: .direct, symbol: "bolt.fill")
        }
        .padding(T.space1)
        .frame(width: contentWidth)
        .background(self.nativeControlSurface(cornerRadius: SegmentedControlStyle.mode.cornerRadius))
    }

    func modeSegmentButton(title: String, mode: CoreMode, symbol: String) -> some View {
        let style = SegmentedControlStyle.mode
        let selected = appViewModel.currentMode == mode
        let switchingThisMode = switchingMode == mode
        let hovered = hoveredMode == mode

        return Button {
            guard appViewModel.isModeSwitchEnabled, switchingMode == nil,
                  mode != appViewModel.currentMode else { return }

            switchingMode = mode
            Task { @MainActor in
                await appViewModel.switchMode(to: mode)
                switchingMode = nil
            }
        } label: {
            HStack(spacing: T.space4) {
                Image(systemName: symbol)
                    .foregroundStyle(selected
                        ? self.segmentedAccentColor(style: style).opacity(isDarkAppearance ? 0.88 : 0.80)
                        : nativeTertiaryLabel)
                Text(title)
                    .lineLimit(1)
            }
            .font(.app(size: T.FontSize.callout, weight: .semibold))
            .foregroundStyle(self.segmentedLabelColor(style: style, selected: selected, hovered: hovered))
            .frame(maxWidth: .infinity)
            .frame(height: style.rowHeight)
            .overlay(alignment: .trailing) {
                if switchingThisMode {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 10, height: 10)
                        .tint(self.segmentedAccentColor(style: style))
                        .padding(.trailing, T.space6)
                }
            }
            .background(self.segmentedButtonBackground(style: style, selected: selected, hovered: hovered))
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!appViewModel.isModeSwitchEnabled || switchingMode != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hoveredMode = self.nextHovered(current: hoveredMode, target: mode, isHovering: $0) }
        .animation(self.tabSelectionAnimation, value: appViewModel.currentMode)
        .animation(.easeOut(duration: 0.12), value: hoveredMode)
    }

    var topTabs: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                self.tabSegmentButton(tab)
            }
        }
        .frame(width: contentWidth)
    }

    func tabSegmentButton(_ tab: RootTab) -> some View {
        let style = SegmentedControlStyle.tab
        let selected = self.rootViewModel.currentTab == tab
        let hovered = hoveredTab == tab

        return Button {
            guard self.rootViewModel.currentTab != tab else { return }
            self.previousTab = self.rootViewModel.currentTab
            self.rootViewModel.syncCurrentTab(tab)
        } label: {
            Text(self.tr(tab.titleKey))
                .font(.app(size: T.FontSize.body, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(T.minimumScale)
                .foregroundStyle(self.segmentedLabelColor(style: style, selected: selected, hovered: hovered))
                .frame(maxWidth: .infinity)
                .frame(height: style.rowHeight)
                .background(self.tabButtonBackground(selected: selected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hoveredTab = self.nextHovered(current: hoveredTab, target: tab, isHovering: $0) }
        .animation(self.tabSelectionAnimation, value: self.rootViewModel.currentTab)
        .animation(.easeOut(duration: 0.12), value: hoveredTab)
    }

    @ViewBuilder
    private func tabButtonBackground(selected: Bool) -> some View {
        if selected {
            FolderTabShape()
                .fill(self.nativeControlFill.opacity(isDarkAppearance ? 0.54 : 0.38))
                .overlay {
                    FolderTabShape().stroke(self.nativeSeparator.opacity(0.65), lineWidth: T.stroke)
                }
                .matchedGeometryEffect(
                    id: SegmentedControlStyle.tab.selectionBackgroundID,
                    in: self.segmentedSelectionNamespace)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                self.nativeSeparator.opacity(0.65).frame(height: T.stroke)
            }
        }
    }

    @ViewBuilder
    private func segmentedButtonBackground(
        style: SegmentedControlStyle,
        selected: Bool,
        hovered: Bool) -> some View
    {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        if selected {
            shape
                .fill(self.segmentedSelectionFill(style: style))
                .overlay {
                    shape.stroke(
                        self.segmentedSelectionBorder(style: style),
                        lineWidth: T.stroke)
                }
                .matchedGeometryEffect(id: style.selectionBackgroundID, in: self.segmentedSelectionNamespace)
        } else if hovered {
            shape.fill(self.segmentedHoverFill(style: style))
        } else {
            Color.clear
        }
    }

    private func segmentedLabelColor(style: SegmentedControlStyle, selected: Bool, hovered: Bool) -> Color {
        if selected {
            return style.isMode
                ? nativePrimaryLabel.opacity(style.selectedForegroundOpacity(isDark: isDarkAppearance))
                : nativePrimaryLabel
        }
        if hovered {
            return nativePrimaryLabel.opacity(isDarkAppearance ? 0.82 : (style.isMode ? 0.72 : 0.74))
        }
        return nativeSecondaryLabel
    }

    private func segmentedAccentColor(style: SegmentedControlStyle) -> Color {
        isDarkAppearance
            ? (style.isMode ? Color(red: 0.56, green: 0.77, blue: 0.98) : Color(red: 0.50, green: 0.72, blue: 0.95))
            : (style.isMode ? Color(red: 0.16, green: 0.36, blue: 0.67) : Color(red: 0.20, green: 0.40, blue: 0.71))
    }

    private func segmentedSelectionFill(style: SegmentedControlStyle) -> Color {
        self.segmentedAccentColor(style: style).opacity(style.selectedFillOpacity(isDark: isDarkAppearance))
    }

    private func segmentedSelectionBorder(style: SegmentedControlStyle) -> Color {
        self.segmentedAccentColor(style: style).opacity(style.selectedBorderOpacity(isDark: isDarkAppearance))
    }

    private func segmentedHoverFill(style: SegmentedControlStyle) -> Color {
        nativeHoverFill.opacity(style.hoverFillOpacity(isDark: isDarkAppearance))
    }
}
