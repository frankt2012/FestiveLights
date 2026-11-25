import AppKit
import SwiftUI

struct ControlsView: View {
    @ObservedObject var settings: Settings
    let onResetTree: () -> Void
    @ObservedObject var loginManager: LoginItemManager
    @ObservedObject var updateChecker: UpdateChecker

    private let width: CGFloat = 332
    private let height: CGFloat = 740

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            masterControl

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    section(title: "Animation") {
                        modeGrid
                    }

                    section(title: "Colors") {
                        themeGrid
                    }

                    controlsCard

                    section(title: "Layering") {
                        layeringControl
                    }

                    section(title: "Interaction") {
                        VStack(spacing: 9) {
                            interactionControl

                            Rectangle()
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 1)

                            treeControl
                        }
                    }

                    section(title: "Tree Lights") {
                        treeLightsControl
                    }

                    section(title: "Train") {
                        trainControl
                    }

                    section(title: "App") {
                        appControls
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            divider
            footer
        }
        .padding(16)
        .frame(width: width, height: height)
        .onAppear {
            loginManager.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: settings.theme.colors.map { $0.swiftUIColor },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: settings.theme.colors[0].swiftUIColor.opacity(0.45), radius: 6)

                    Image(systemName: settings.isOn ? "lightbulb.led.fill" : "lightbulb.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("FestiveLights")
                    .font(.system(size: 14, weight: .semibold))
                Text(settings.isOn ? "Lights on · \(settings.theme.title)" : "Lights off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $settings.isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(settings.isOn ? "Turn the lights off" : "Turn the lights on")
        }
    }

    // MARK: - Animation

    private var modeGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 7) {
            ForEach(LightMode.allCases) { mode in
                modeChip(mode)
            }
            shortcutChip
        }
    }

    private func modeChip(_ mode: LightMode) -> some View {
        let isSelected = settings.mode == mode
        return Button {
            settings.mode = mode
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 15)
                Text(mode.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.075),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(mode.title)
    }

    private var shortcutChip: some View {
        VStack(alignment: .leading, spacing: 2) {
            shortcutLine(keys: HotKeyManager.toggleShortcut, label: "Toggle")
            shortcutLine(keys: HotKeyManager.panelShortcut, label: "Panel")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .help("Global shortcuts: ⌥⌘L toggles the lights, ⌥⌘P opens this panel")
    }

    private func shortcutLine(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Themes

    private var themeGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 7) {
            ForEach(LightTheme.allCases) { theme in
                themeChip(theme)
            }
        }
    }

    private func themeChip(_ theme: LightTheme) -> some View {
        let isSelected = settings.theme == theme
        return Button {
            settings.theme = theme
        } label: {
            HStack(spacing: 7) {
                HStack(spacing: 2.5) {
                    ForEach(Array(theme.colors.prefix(4).enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 9, height: 9)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }

                Text(theme.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7.5)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.075),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(theme.title)
    }

    // MARK: - Sliders

    private var controlsCard: some View {
        VStack(spacing: 11) {
            sliderRow(
                title: "Brightness",
                symbol: "sun.max.fill",
                value: $settings.glow,
                range: Settings.glowRange,
                readout: "\(Int(round(settings.glow * 100)))%"
            )

            sliderRow(
                title: "Animation Speed",
                symbol: "speedometer",
                value: $settings.speed,
                range: Settings.speedRange,
                readout: String(format: "%.1f×", settings.speed)
            )
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func sliderRow(
        title: String,
        symbol: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        readout: String
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(readout)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(.accentColor)
        }
    }

    // MARK: - Layering

    private var layeringControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Layering", selection: $settings.layering) {
                ForEach(OverlayLayering.allCases) { layering in
                    Text(layering.title).tag(layering)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            Text(settings.layering.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Interaction

    private var interactionControl: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Interactive Mouse Sway")
                    .font(.system(size: 11, weight: .medium))
                Text("Bulbs gently swing when the cursor moves nearby.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $settings.mouseSway)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Turn interactive mouse sway on or off")
        }
    }

    private var treeControl: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Christmas Tree")
                    .font(.system(size: 11, weight: .medium))
                Text("Drag it around the desktop.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            Button("Reset") {
                onResetTree()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .help("Move the tree back to the bottom-right corner")

            Toggle("", isOn: $settings.showTree)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Show or hide the Christmas tree")
        }
    }

    // MARK: - Tree lights

    private var treeLightsControl: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Text("Color")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                Picker("Color", selection: $settings.treeLightSource) {
                    ForEach(TreeLightSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 112)

                Spacer(minLength: 4)

                Text("Style")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                Picker("Style", selection: $settings.treeLightStyle) {
                    ForEach(TreeLightStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 90)
            }

            HStack(spacing: 7) {
                Text("Glow")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                Slider(value: $settings.treeLightGlow, in: Settings.treeGlowRange)
                    .controlSize(.small)
                    .tint(.accentColor)

                Text("\(Int(round(settings.treeLightGlow * 100)))%")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    // MARK: - Train

    private var trainControl: some View {
        HStack(spacing: 8) {
            Toggle("Steam Train", isOn: $settings.showTrain)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .help("Show or hide the steam train")

            Spacer(minLength: 8)

            Picker("Cars", selection: $settings.trainCarType) {
                ForEach(TrainCarType.allCases) { carType in
                    Text(carType.title).tag(carType)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
    }

    // MARK: - Master power

    private var masterControl: some View {
        HStack(spacing: 8) {
            Image(systemName: settings.allDecorationsOn ? "power.circle.fill" : "power.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settings.allDecorationsOn ? Color.accentColor : Color.secondary)

            Text("All Decorations")
                .font(.system(size: 11, weight: .medium))

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(
                    get: { settings.allDecorationsOn },
                    set: { settings.setAllDecorations($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help("Turn the lights, tree and train off or on together")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - App settings

    private var appControls: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 11, weight: .medium))
                    Text(loginManager.statusDetail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { loginManager.isEnabled },
                        set: { loginManager.setEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Start FestiveLights automatically when you log in")
            }

            if loginManager.requiresApproval {
                Button("Open Login Items…") {
                    loginManager.openLoginItemsSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                        .font(.system(size: 11, weight: .medium))
                    Text(updateChecker.statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button(updateChecker.isChecking ? "Checking…" : "Check Now") {
                    updateChecker.check()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .disabled(updateChecker.isChecking)
            }

            if let update = updateChecker.availableUpdate {
                HStack(spacing: 8) {
                    Text("Version \(update.version)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 6)

                    Button("Download") {
                        updateChecker.openDownload()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help(update.notes ?? "Open the update download page")
                }
            }
        }
    }

    // MARK: - Footer

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("Click-through · all displays")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 6)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit FestiveLights")
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 7),
            GridItem(.flexible(), spacing: 7)
        ]
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private extension LightColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}
