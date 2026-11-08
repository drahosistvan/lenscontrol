import SwiftUI

/// What the name field is for.
enum PresetEdit: Equatable {
    case save
    case rename(Preset)

    var title: String {
        switch self {
        case .save: return "Save Current Settings as Preset"
        case .rename(let preset): return "Rename “\(preset.name)”"
        }
    }

    var verb: String {
        switch self {
        case .save: return "Save"
        case .rename: return "Rename"
        }
    }
}

// MARK: - Popover

/// Popover presets: a pop-up (tinted when the camera matches a preset, "Custom"
/// otherwise) with a ⋯ actions menu. Saving or renaming swaps the row for an
/// inline name field — ⏎ saves, esc cancels.
struct PresetsSection: View {
    @Environment(CameraModel.self) private var model
    @State private var edit: PresetEdit?

    var body: some View {
        FormSection(title: "Presets") {
            if let edit {
                PresetNameEditor(edit: edit, compact: true) { self.edit = nil }
            } else {
                FormRow(label: "Preset") {
                    HStack(spacing: 6) {
                        picker
                        actionsMenu
                    }
                }
            }
        }
    }

    private var picker: some View {
        let active = model.activePreset
        return Picker("Preset", selection: Binding(
            get: { active?.id.uuidString ?? "custom" },
            set: { id in
                if let preset = model.presets.presets.first(where: { $0.id.uuidString == id }) {
                    model.apply(preset)
                }
            }
        )) {
            if active == nil {
                Text("Custom").tag("custom")
            }
            ForEach(model.presets.presets) { preset in
                Text(preset.name).tag(preset.id.uuidString)
            }
        }
        .labelsHidden()
        .tint(active == nil ? nil : .accentColor)
        .foregroundStyle(active == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
        .frame(maxWidth: Metrics.popupMaxWidth, alignment: .leading)
        .help(active.map { "Camera matches “\($0.name)” · ⌘1–⌘9 apply presets" } ?? "⌘1–⌘9 apply presets")
    }

    private var actionsMenu: some View {
        let selected = model.presets.preset(id: model.selectedPresetID)
        return Menu {
            Button("Save Current as…") { edit = .save }
            if let selected {
                Button("Update “\(selected.name)”") { model.updatePreset(selected.id) }
                Button("Rename “\(selected.name)”…") { edit = .rename(selected) }
                Button("Delete “\(selected.name)”") { model.deletePreset(selected.id) }
            }
            Divider()
            Text("⌘1–⌘9 apply presets in order")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Preset actions")
    }
}

// MARK: - Window

/// Window presets: a list with ⌘ shortcuts (click selects, double-click applies)
/// and +/− · Update · Rename… · Apply beneath; naming happens in a sheet.
struct PresetsListSection: View {
    @Environment(CameraModel.self) private var model
    @State private var edit: PresetEdit?

    var body: some View {
        let active = model.activePreset
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Presets")
                Spacer()
                Text(active.map { "Matches “\($0.name)”" } ?? "Custom")
                    .font(.system(size: 11))
                    .foregroundStyle(active == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .fixedSize()
            }
            list(active: active)
            buttons
        }
        .sheet(item: Binding(
            get: { edit.map(SheetItem.init) },
            set: { edit = $0?.edit }
        )) { item in
            PresetNameEditor(edit: item.edit, compact: false) { edit = nil }
                .environment(model)
                .padding(20)
                .frame(width: 380)
        }
    }

    private func list(active: Preset?) -> some View {
        VStack(spacing: 1) {
            if model.presets.presets.isEmpty {
                Text("No presets yet. Save the current settings with +.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(Array(model.presets.presets.enumerated()), id: \.element.id) { index, preset in
                let isActive = preset.id == active?.id
                let isSelected = preset.id == model.selectedPresetID
                HStack(spacing: 8) {
                    Circle()
                        .fill(isActive ? Color.accentColor : .clear)
                        .frame(width: 6, height: 6)
                    Text(preset.name)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Spacer()
                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    isActive ? AnyShapeStyle(Color.accentColor.opacity(0.14))
                        : isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.apply(preset) }
                .simultaneousGesture(TapGesture().onEnded { model.selectedPresetID = preset.id })
                .help("Double-click to apply")
            }
        }
        .padding(4)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var buttons: some View {
        let selected = model.presets.preset(id: model.selectedPresetID)
        return HStack(spacing: 6) {
            ControlGroup {
                Button { edit = .save } label: { Image(systemName: "plus") }
                    .help("Save current as…")
                Button { if let selected { model.deletePreset(selected.id) } } label: { Image(systemName: "minus") }
                    .help("Delete selected preset")
                    .disabled(selected == nil)
            }
            .fixedSize()
            Button("Update") { if let selected { model.updatePreset(selected.id) } }
                .help("Overwrite the selected preset with the camera’s current values")
                .disabled(selected == nil)
            Button("Rename…") { if let selected { edit = .rename(selected) } }
                .disabled(selected == nil)
            Spacer()
            Button("Apply") { if let selected { model.apply(selected) } }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
        }
        .controlSize(.small)
    }

    private struct SheetItem: Identifiable {
        let edit: PresetEdit
        var id: String {
            switch edit {
            case .save: return "save"
            case .rename(let preset): return "rename-\(preset.id)"
            }
        }
    }
}

// MARK: - Shared name editor

/// Name field for saving or renaming. Compact is the popover's inline version;
/// the full one is the window sheet's content.
struct PresetNameEditor: View {
    @Environment(CameraModel.self) private var model
    let edit: PresetEdit
    let compact: Bool
    let done: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    /// Saving under an existing name replaces that preset.
    private var replaces: Preset? {
        guard case .save = edit, !trimmed.isEmpty else { return nil }
        return model.presets.presets.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private var note: String {
        switch edit {
        case .rename: return "Values stay the same."
        case .save:
            let next = model.presets.presets.count + 1
            return compact
                ? "All ten values · ⌘\(next)"
                : "Stores all ten values: shutter, aperture, ISO, Auto ISO + max, EV, white balance, kelvin, AF mode and mic. Apply later with ⌘\(next)."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text(edit.title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
            if !compact {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !compact {
                    Text("Name").foregroundStyle(.secondary)
                }
                TextField("Preset name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand(perform: done)
            }
            if let replaces {
                Text(compact
                     ? "Replaces the existing “\(replaces.name)”."
                     : "A preset named “\(replaces.name)” exists. Saving replaces it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if compact {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: done)
                    .keyboardShortcut(.cancelAction)
                Button(edit.verb, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
            .controlSize(compact ? .small : .regular)
        }
        .onAppear {
            if case .rename(let preset) = edit { name = preset.name }
            focused = true
        }
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        switch edit {
        case .save: model.saveCurrentPreset(named: trimmed)
        case .rename(let preset): model.renamePreset(preset.id, to: trimmed)
        }
        done()
    }
}
