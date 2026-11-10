import AppKit
import SwiftUI

enum OverlayContextMenu {
    // Matches roughly where a normal NSMenuItem's title starts (past the checkmark/state-image
    // gutter), so hosted SwiftUI rows visually line up with "Pen", "Line", etc. instead of the
    // menu's raw content edge.
    private static let rowLeadingPad: CGFloat = 24
    private static let rowTrailingPad: CGFloat = 14

    static func build(appState: AppState, target: OverlayView, hudController: HUDController, hitAnnotationID: UUID?) -> NSMenu {
        let menu = NSMenu()

        // Right-clicking an existing layer edits that layer's own color/width/style/size directly
        // (via editingAnnotationID below) rather than the current tool's defaults for future
        // annotations — so the rows shown reflect the layer's kind, not whichever tool is active.
        let hitAnnotation = hitAnnotationID.flatMap { id in appState.annotations.first { $0.id == id } }
        let isEditingLayer = hitAnnotation != nil
        let rowsTool: ToolType? = isEditingLayer ? hitAnnotation?.kind.asToolType : appState.currentTool

        if let hitAnnotationID {
            let deleteItem = NSMenuItem(title: "Delete Layer", action: #selector(OverlayView.deleteHitLayer(_:)), keyEquivalent: "")
            deleteItem.representedObject = hitAnnotationID
            deleteItem.target = target
            menu.addItem(deleteItem)
            menu.addItem(.separator())
        }

        var sliderItemIndex: Int?
        var addedAnyRow = false
        if let rowsTool {
            if rowsTool.usesColor {
                menu.addItem(hostedItem(ColorRow(appState: appState, hudController: hudController, tool: rowsTool, editingAnnotationID: hitAnnotationID, onSelect: { menu.cancelTracking() })))
                addedAnyRow = true
            }
            if rowsTool.usesLineStyle || rowsTool.usesShapeStyle {
                menu.addItem(hostedItem(StyleRow(appState: appState, hudController: hudController, tool: rowsTool, editingAnnotationID: hitAnnotationID, allowsFilled: rowsTool.usesShapeStyle, onSelect: { menu.cancelTracking() })))
                addedAnyRow = true
            }
            if rowsTool.usesFontStyle {
                menu.addItem(hostedItem(FontStyleRow(appState: appState, hudController: hudController, tool: rowsTool, editingAnnotationID: hitAnnotationID, onSelect: { menu.cancelTracking() })))
                addedAnyRow = true
            }
            if rowsTool.usesWidth {
                sliderItemIndex = menu.items.count
                menu.addItem(hostedItem(widthRow(appState: appState, hudController: hudController, editingAnnotationID: hitAnnotationID, sliderWidth: 160)))
                addedAnyRow = true
            } else if rowsTool.usesFontSize {
                sliderItemIndex = menu.items.count
                menu.addItem(hostedItem(fontSizeRow(appState: appState, hudController: hudController, editingAnnotationID: hitAnnotationID, sliderWidth: 160)))
                addedAnyRow = true
            }

            // The "next counter value" stepper only makes sense for annotations not yet placed.
            if rowsTool == .counter, !isEditingLayer {
                menu.addItem(.separator())
                menu.addItem(hostedItem(CounterAdjustRow(appState: appState)))
                addedAnyRow = true
            }
        }
        if addedAnyRow {
            menu.addItem(.separator())
        }

        for t in ToolType.allCases {
            let item = NSMenuItem(title: t.displayName, action: #selector(OverlayView.contextMenuSelectTool(_:)), keyEquivalent: String(t.keyEquivalent))
            // Default key-equivalent modifier mask is .command, which is why this used to render
            // as "⌘P" — these shortcuts are actually bare letters (no modifier), matching how
            // OverlayView.keyDown handles them directly.
            item.keyEquivalentModifierMask = []
            item.representedObject = t
            item.target = target
            item.state = (t == appState.currentTool) ? .on : .off
            menu.addItem(item)
        }

        // Only now, with the (width-dominant) tool list in place, is the menu's real width known.
        // Rebuild the slider row using that measured width so it actually spans edge-to-edge,
        // instead of an upfront guess that's rarely exactly right.
        if let sliderItemIndex, let rowsTool {
            let actualWidth = max(120, menu.size.width - rowLeadingPad - rowTrailingPad)
            let rebuilt = rowsTool.usesWidth
                ? hostedItem(widthRow(appState: appState, hudController: hudController, editingAnnotationID: hitAnnotationID, sliderWidth: actualWidth))
                : hostedItem(fontSizeRow(appState: appState, hudController: hudController, editingAnnotationID: hitAnnotationID, sliderWidth: actualWidth))
            menu.removeItem(at: sliderItemIndex)
            menu.insertItem(rebuilt, at: sliderItemIndex)
        }

        return menu
    }

    private static func hostedItem<V: View>(_ view: V) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view
            .padding(.leading, rowLeadingPad).padding(.trailing, rowTrailingPad).padding(.vertical, 6))
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    private static func widthRow(appState: AppState, hudController: HUDController, editingAnnotationID: UUID?, sliderWidth: CGFloat) -> SliderRow {
        SliderRow(
            label: "Width", range: 1...15, sliderWidth: sliderWidth,
            appState: appState, hudController: hudController, editingAnnotationID: editingAnnotationID,
            annotationKeyPath: \.lineWidth,
            toolValue: { appState.toolSettings.width(for: appState.currentTool) },
            setToolValue: { appState.toolSettings.setWidth(for: appState.currentTool, $0) }
        )
    }

    private static func fontSizeRow(appState: AppState, hudController: HUDController, editingAnnotationID: UUID?, sliderWidth: CGFloat) -> SliderRow {
        SliderRow(
            label: "Size", range: 8...48, sliderWidth: sliderWidth,
            appState: appState, hudController: hudController, editingAnnotationID: editingAnnotationID,
            annotationKeyPath: \.fontSize,
            toolValue: { appState.toolSettings.fontSize(for: appState.currentTool) },
            setToolValue: { appState.toolSettings.setFontSize(for: appState.currentTool, $0) }
        )
    }
}

/// Shared rendering for a horizontal row of tappable circular option icons — color swatches,
/// line/shape style symbols, font-style glyphs. ColorRow/StyleRow/FontStyleRow differ only in what
/// each option looks like and what selecting one does (which property it writes), so that's all
/// they each still own; the icon sizing/selection-ring/tap-handling below was identical three times.
private struct PickerRow<Option, ID: Hashable>: View {
    let options: [Option]
    let id: KeyPath<Option, ID>
    let isSelected: (Option) -> Bool
    let icon: (Option) -> AnyView
    let onPick: (Option) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: id) { option in
                icon(option)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.primary, lineWidth: isSelected(option) ? 2 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(option) }
            }
        }
    }
}

private struct ColorRow: View {
    let appState: AppState
    let hudController: HUDController
    let tool: ToolType
    let editingAnnotationID: UUID?
    let onSelect: () -> Void
    @State private var selectedHex: String

    init(appState: AppState, hudController: HUDController, tool: ToolType, editingAnnotationID: UUID?, onSelect: @escaping () -> Void) {
        self.appState = appState
        self.hudController = hudController
        self.tool = tool
        self.editingAnnotationID = editingAnnotationID
        self.onSelect = onSelect
        if let editingAnnotationID, let annotation = appState.annotations.first(where: { $0.id == editingAnnotationID }) {
            _selectedHex = State(initialValue: annotation.color.hexString)
        } else {
            _selectedHex = State(initialValue: appState.toolSettings.color(for: tool))
        }
    }

    var body: some View {
        PickerRow(
            options: ColorPalette.entries,
            id: \.color,
            isSelected: { selectedHex == $0.color.hexString },
            icon: { AnyView(Circle().fill(Color(nsColor: $0.color))) },
            onPick: { entry in
                selectedHex = entry.color.hexString
                if let editingAnnotationID, let index = appState.annotations.firstIndex(where: { $0.id == editingAnnotationID }) {
                    appState.annotations[index].color = entry.color
                    appState.contentDidChange?()
                }
                // Editing a placed layer also updates the tool's default, so the next new
                // annotation of this kind picks up whatever was just chosen for this one.
                appState.toolSettings.setColor(for: tool, entry.color.hexString)
                hudController.show(text: entry.name)
                onSelect()
            }
        )
    }
}

private struct StyleRow: View {
    let appState: AppState
    let hudController: HUDController
    let tool: ToolType
    let editingAnnotationID: UUID?
    let allowsFilled: Bool
    let onSelect: () -> Void
    @State private var selected: LineStyle

    init(appState: AppState, hudController: HUDController, tool: ToolType, editingAnnotationID: UUID?, allowsFilled: Bool, onSelect: @escaping () -> Void) {
        self.appState = appState
        self.hudController = hudController
        self.tool = tool
        self.editingAnnotationID = editingAnnotationID
        self.allowsFilled = allowsFilled
        self.onSelect = onSelect
        if let editingAnnotationID, let annotation = appState.annotations.first(where: { $0.id == editingAnnotationID }) {
            _selected = State(initialValue: annotation.lineStyle)
        } else {
            _selected = State(initialValue: appState.toolSettings.lineStyle(for: tool))
        }
    }

    private var options: [LineStyle] { LineStyle.options(allowsFilled: allowsFilled) }

    var body: some View {
        PickerRow(
            options: options,
            id: \.self,
            isSelected: { selected == $0 },
            icon: { style in
                // Resizable + scaledToFit forces every symbol (circle/circle.dashed/circle.dotted/
                // circle.fill) into the exact same glyph box — their natural ink extents differ
                // enough that a plain fixed .frame() left them visibly mismatched in size/position.
                AnyView(
                    Image(systemName: style.symbolName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                )
            },
            onPick: { style in
                selected = style
                if let editingAnnotationID, let index = appState.annotations.firstIndex(where: { $0.id == editingAnnotationID }) {
                    appState.annotations[index].lineStyle = style
                    appState.contentDidChange?()
                }
                // Editing a placed layer also updates the tool's default — see ColorRow.
                appState.toolSettings.setLineStyle(for: tool, style)
                hudController.show(text: style.displayName)
                onSelect()
            }
        )
    }
}

private struct FontStyleRow: View {
    let appState: AppState
    let hudController: HUDController
    let tool: ToolType
    let editingAnnotationID: UUID?
    let onSelect: () -> Void
    @State private var selected: TextFontStyle

    init(appState: AppState, hudController: HUDController, tool: ToolType, editingAnnotationID: UUID?, onSelect: @escaping () -> Void) {
        self.appState = appState
        self.hudController = hudController
        self.tool = tool
        self.editingAnnotationID = editingAnnotationID
        self.onSelect = onSelect
        if let editingAnnotationID, let annotation = appState.annotations.first(where: { $0.id == editingAnnotationID }) {
            _selected = State(initialValue: annotation.fontStyle)
        } else {
            _selected = State(initialValue: appState.toolSettings.fontStyle(for: tool))
        }
    }

    var body: some View {
        PickerRow(
            options: TextFontStyle.allCases,
            id: \.self,
            isSelected: { selected == $0 },
            icon: { style in
                // The icon IS the letter "A" set in that font — no SF Symbol stand-in reads as
                // clearly as just showing the font itself.
                AnyView(Text("A").font(Font(style.font(size: 15, bold: false))))
            },
            onPick: { style in
                selected = style
                if let editingAnnotationID, let index = appState.annotations.firstIndex(where: { $0.id == editingAnnotationID }) {
                    appState.annotations[index].fontStyle = style
                    appState.contentDidChange?()
                }
                // Editing a placed layer also updates the tool's default — see ColorRow.
                appState.toolSettings.setFontStyle(for: tool, style)
                hudController.show(text: style.displayName)
                onSelect()
            }
        )
    }
}

private struct CounterAdjustRow: View {
    let appState: AppState
    @State private var value: Int

    init(appState: AppState) {
        self.appState = appState
        _value = State(initialValue: appState.nextCounterValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Next")
            Spacer()
            Button {
                value = max(1, value - 1)
                appState.nextCounterValue = value
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            Text("\(value)").monospacedDigit().frame(minWidth: 20)
            Button {
                value += 1
                appState.nextCounterValue = value
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            Button {
                value = 1
                appState.nextCounterValue = 1
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .padding(.leading, 6)
            .help("Reset count")
        }
    }
}

/// Shared slider row for Width/Size — both read/write either the hit annotation directly (when
/// editing an existing layer) or the tool's default (when configuring what gets drawn next). Note:
/// unlike Color/Style/FontStyle, editing an existing layer here does NOT also update the tool
/// default (matches prior behavior — only the two setter closures below touch tool defaults, and
/// those only run in the non-editing branch).
private struct SliderRow: View {
    let label: String
    let range: ClosedRange<CGFloat>
    let sliderWidth: CGFloat
    let appState: AppState
    let hudController: HUDController
    let editingAnnotationID: UUID?
    let annotationKeyPath: WritableKeyPath<Annotation, CGFloat>
    let toolValue: () -> CGFloat
    let setToolValue: (CGFloat) -> Void

    var body: some View {
        HStack {
            Text(label)
            // No `step:` argument — SwiftUI draws tick marks whenever a Slider has one. Rounding
            // in the setter enforces whole-number steps without the visual dots.
            Slider(value: Binding(
                get: {
                    if let editingAnnotationID, let annotation = appState.annotations.first(where: { $0.id == editingAnnotationID }) {
                        return annotation[keyPath: annotationKeyPath]
                    }
                    return toolValue()
                },
                set: { newValue in
                    let rounded = newValue.rounded()
                    if let editingAnnotationID, let index = appState.annotations.firstIndex(where: { $0.id == editingAnnotationID }) {
                        appState.annotations[index][keyPath: annotationKeyPath] = rounded
                        appState.contentDidChange?()
                    } else {
                        setToolValue(rounded)
                    }
                    hudController.show(text: "\(label) \(Int(rounded))")
                }
            ), in: range)
        }
        .frame(width: sliderWidth)
    }
}
