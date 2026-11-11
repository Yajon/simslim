import AppKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var localization: Localization
  @State private var searchText = ""
  @State private var searchIsExpanded = false
  @State private var managementSheet: SimulatorManagementSheet?
  @State private var slimmingMode: SlimmingMode = .memory

  private var filteredDevices: [SimulatorDevice] {
    guard !searchText.isEmpty else { return model.devices }
    return model.devices.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
        || $0.udid.localizedCaseInsensitiveContains(searchText)
        || $0.runtimeName.localizedCaseInsensitiveContains(searchText)
    }
  }

  private var filteredUDIDs: Set<String> {
    Set(filteredDevices.map(\.udid))
  }

  private var singleSelectedDevice: SimulatorDevice? {
    let selected = model.selectedDevices
    return selected.count == 1 ? selected[0] : nil
  }

  private var selectedCleanableDiskCategories: [DiskCleanupCategory] {
    model.diskCleanupCategories.filter {
      $0.canClean && model.selectedDiskCleanupCategoryIDs.contains($0.id)
    }
  }

  private var automaticDiskAnalysisID: String {
    guard slimmingMode == .disk else { return "memory" }
    return "disk:" + model.selectedUDIDs.sorted().joined(separator: ",")
  }

  var body: some View {
    NavigationSplitView {
      ProfileSidebar(mode: $slimmingMode)
        .navigationSplitViewColumnWidth(min: 340, ideal: 390, max: 460)
    } detail: {
      VStack(spacing: 0) {
        header
        Divider()
        selectionBar
        Divider()
        simulatorTable
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .layoutPriority(1)
        Divider()
        ActivityPanel()
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .toolbar {
      if slimmingMode == .memory {
        ToolbarItem(placement: .automatic) {
          Button {
            managementSheet = .slimmingRecommendation(model.selectedDevices)
          } label: {
            ToolbarActionLabel(tr("Slim"), systemImage: "minus.circle")
          }
          .disabled(model.selectionCount == 0 || !model.canStartBatchOnSelection)
          .help(tr("Apply the selected service profile"))
        }

        ToolbarItem(placement: .automatic) {
          Button {
            Task { await model.restoreSelection() }
          } label: {
            ToolbarActionLabel(tr("Unslim"), systemImage: "plus.circle")
          }
          .disabled(model.selectionCount == 0 || !model.canStartBatchOnSelection)
          .help(tr("Restore all SimSlim-managed services"))
        }
      } else {
        ToolbarItem(placement: .automatic) {
          Button(role: .destructive) {
            managementSheet = .diskCleanup(model.selectedDevices, selectedCleanableDiskCategories)
          } label: {
            ToolbarActionLabel(tr("Clean Disk"), systemImage: "externaldrive.badge.xmark")
          }
          .disabled(!model.canCleanDiskSelection || !model.canStartBatchOnSelection)
          .help(tr("Permanently clean the selected disk categories"))
        }
      }

      ToolbarItem { Spacer() }

      ToolbarItemGroup(placement: .automatic) {
        Button {
          guard let device = singleSelectedDevice else { return }
          managementSheet = .clone(device)
        } label: {
          ToolbarActionLabel(tr("Clone"), systemImage: "plus.square.on.square")
        }
        .disabled(singleSelectedDevice == nil || model.isSelectionBusy)
        .help(tr("Clone for backup or general-purpose use"))

        Button(role: .destructive) {
          managementSheet = .erase(model.selectedDevices)
        } label: {
          ToolbarActionLabel(tr("Erase"), systemImage: "eraser")
        }
        .disabled(model.selectionCount == 0 || !model.canStartBatchOnSelection)
        .help(tr("Erase Simulator"))

        Button(role: .destructive) {
          managementSheet = .delete(model.selectedDevices)
        } label: {
          ToolbarActionLabel(tr("Delete"), systemImage: "trash")
        }
        .disabled(model.selectionCount == 0 || !model.canStartBatchOnSelection)
        .help(tr("Delete Simulator"))
      }

      ToolbarItem { Spacer() }

      ToolbarItemGroup(placement: .automatic) {
        Button {
          guard let device = singleSelectedDevice else { return }
          Task { await model.bootSimulator(device) }
        } label: {
          ToolbarActionLabel(tr("Boot"), systemImage: "play.fill")
        }
        .disabled(
          singleSelectedDevice == nil || singleSelectedDevice?.isBooted == true
            || model.isSelectionBusy
        )
        .help(tr("Boot Simulator"))

        Button {
          guard let device = singleSelectedDevice else { return }
          Task { await model.shutdownSimulator(device) }
        } label: {
          ToolbarActionLabel(tr("Kill"), systemImage: "stop.fill")
        }
        .disabled(
          singleSelectedDevice == nil || singleSelectedDevice?.isBooted == false
            || model.isSelectionBusy
        )
        .help(tr("Shut Down Simulator"))

        Button {
          guard let device = singleSelectedDevice else { return }
          managementSheet = .rename(device)
        } label: {
          ToolbarActionLabel(tr("Rename"), systemImage: "pencil")
        }
        .disabled(singleSelectedDevice == nil || model.isSelectionBusy)
        .help(tr("Rename Simulator"))
      }

      ToolbarItem { Spacer() }

      ToolbarItemGroup(placement: .automatic) {
        Button {
          Task { await model.refresh() }
        } label: {
          ToolbarActionLabel(tr("Refresh"), systemImage: "arrow.clockwise")
        }
        .disabled(model.isBusy)
        .help(tr("Refresh simulator status"))

        Menu {
          Button(tr("Select Visible")) { model.select(filteredUDIDs) }
            .disabled(filteredDevices.isEmpty)
          Button(tr("Clear Selection")) { model.clearSelection() }
            .disabled(model.selectionCount == 0)
        } label: {
          ToolbarActionLabel(tr("Selection"), systemImage: "checklist")
        }
        .disabled(model.isBusy)
      }

      ToolbarItem { Spacer() }

      ToolbarItem(placement: .automatic) {
        CollapsibleToolbarSearch(
          text: $searchText,
          prompt: tr("Find a simulator"),
          isExpanded: $searchIsExpanded
        )
      }

      ToolbarItem(placement: .automatic) {
        LanguageMenu()
      }
    }
    .sheet(item: $managementSheet) { sheet in
      managementSheetContent(for: sheet)
    }
    .alert(item: $model.presentedError) { error in
      Alert(
        title: Text(tr("SimSlim couldn’t finish")),
        message: Text(error.message),
        dismissButton: .default(Text(tr("OK")))
      )
    }
    .alert(tr("Language Changed"), isPresented: $localization.showsRestartPrompt) {
      Button(tr("Restart Now")) { localization.relaunch() }
      Button(tr("Later"), role: .cancel) {}
    } message: {
      Text(tr("SimSlim applies the new language after it restarts."))
    }
    .task(id: automaticDiskAnalysisID) {
      guard slimmingMode == .disk, model.selectionCount > 0 else { return }
      await model.analyzeDiskSelectionIfNeeded()
    }
  }

  private var header: some View {
    HStack(spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text(tr("Installed Simulators"))
          .font(.system(size: 27, weight: .bold, design: .rounded))
        Text(lastUpdatedText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      MetricPill(value: "\(model.devices.count)", label: tr("Installed"), color: .blue)
      MetricPill(value: "\(model.bootedCount)", label: tr("Booted"), color: .orange)
      MetricPill(value: "\(model.selectionCount)", label: tr("Selected"), color: .purple)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 15)
  }

  private var selectionBar: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        Button {
          if !filteredDevices.isEmpty && filteredUDIDs.isSubset(of: model.selectedUDIDs) {
            model.select(model.selectedUDIDs.subtracting(filteredUDIDs))
          } else {
            model.select(model.selectedUDIDs.union(filteredUDIDs))
          }
        } label: {
          Image(systemName: selectionAllImage)
            .font(.title3)
            .foregroundStyle(filteredDevices.isEmpty ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(filteredDevices.isEmpty || model.isBusy)
        .help(tr("Select or deselect all visible simulators"))

        if model.selectionCount == 0 {
          Text(
            slimmingMode == .memory
              ? tr("Select simulators to change their service profile")
              : tr("Select simulators to review reclaimable disk data")
          )
          .foregroundStyle(.secondary)
        } else {
          Text(tr("%d selected", model.selectionCount))
            .fontWeight(.semibold)
          if slimmingMode == .memory {
            Text(tr("· profile will disable up to %d services", model.disabledDaemonCount))
              .foregroundStyle(.secondary)
          } else if model.isAnalyzingDisk {
            Text(tr("· analyzing disk usage…"))
              .foregroundStyle(.secondary)
          } else if model.diskAnalysisCoversSelection {
            Text(tr("· %@ selected for cleanup", model.selectedDiskCleanupSizeText()))
              .foregroundStyle(.orange)
          } else {
            Text(tr("· disk analysis pending"))
              .foregroundStyle(.secondary)
          }
        }

        Spacer()
      }
      .controlSize(.regular)

      if let progress = model.batchProgress {
        VStack(spacing: 5) {
          ProgressView(value: progress.fraction)
            .progressViewStyle(.linear)
          HStack {
            Text(progress.runningText)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer()
            Text(tr("%d of %d", progress.completed, progress.total))
              .monospacedDigit()
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 11)
    .background(.bar)
    .animation(.easeInOut(duration: 0.2), value: model.batchProgress)
  }

  private var simulatorTable: some View {
    VStack(spacing: 0) {
      tableHeader
      Divider()

      GeometryReader { geometry in
        Group {
          if model.isRefreshing && model.devices.isEmpty {
            VStack(spacing: 12) {
              ProgressView()
              Text(tr("Loading simulators…"))
                .foregroundStyle(.secondary)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
          } else if filteredDevices.isEmpty {
            SimulatorEmptyState(
              title: searchText.isEmpty ? tr("No Simulators") : tr("No Matches"),
              systemImage: "rectangle.slash",
              description: searchText.isEmpty
                ? tr("Install an iOS, tvOS, watchOS, or visionOS Simulator runtime in Xcode.")
                : tr("Try a different name, UDID, or OS version.")
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
          } else {
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(filteredDevices) { device in
                  SimulatorRow(
                    device: device,
                    diskCleanupCategories: selectedCleanableDiskCategories,
                    managementSheet: $managementSheet
                  )
                  Divider().padding(.leading, 48)
                }
              }
              .frame(width: geometry.size.width, alignment: .top)
            }
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var tableHeader: some View {
    HStack(spacing: 12) {
      Color.clear.frame(width: 30, height: 1)
      Text(tr("SIMULATOR"))
        .frame(minWidth: 255, maxWidth: .infinity, alignment: .leading)
      Text(tr("RUNTIME")).frame(width: 74, alignment: .leading)
      Text(tr("BOOT")).frame(width: 86, alignment: .leading)
      Text(tr("SERVICES")).frame(width: 150, alignment: .leading)
      Text(tr("DISK SIZE")).frame(width: 105, alignment: .leading)
      Text(tr("RAM USAGE")).frame(width: 82, alignment: .leading)
      Color.clear.frame(width: 28, height: 1)
    }
    .font(.system(size: 10, weight: .semibold))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 18)
    .padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
  }

  private var selectionAllImage: String {
    if !filteredDevices.isEmpty && filteredUDIDs.isSubset(of: model.selectedUDIDs) {
      return "checkmark.square.fill"
    }
    if !filteredUDIDs.intersection(model.selectedUDIDs).isEmpty {
      return "minus.square.fill"
    }
    return "square"
  }

  private var lastUpdatedText: String {
    guard let date = model.lastUpdated else { return tr("Loading simulator status…") }
    return tr("Updated %@", date.formatted(date: .omitted, time: .shortened))
  }

  @ViewBuilder
  private func managementSheetContent(for sheet: SimulatorManagementSheet) -> some View {
    switch sheet {
    case .clone(let device):
      SimulatorNameSheet(
        title: tr("Clone Simulator"),
        actionTitle: tr("Clone Simulator"),
        systemImage: "plus.square.on.square",
        explanation: tr(
          "The clone copies the source simulator’s apps, data, settings, and current SimSlim service profile. SimSlim rebases simulator-local links, rebuilds generated app registrations, and audits the running clone for open paths into the source. SimSlim may briefly boot a shutdown source to read its profile, or briefly shut down a booted source to make the copy. The source returns to its original boot state, and the clone finishes shutdown."
        ),
        initialName: tr("%@ Copy", device.name),
        device: device
      ) { name in
        Task { await model.cloneSimulator(device, named: name) }
      }

    case .slimmingRecommendation(let devices):
      SlimmingRecommendationSheet(devices: devices) { device in
        presentAfterSheetDismissal(.clone(device))
      } onContinue: {
        Task { await model.applyProfile(to: devices) }
      }

    case .rename(let device):
      SimulatorNameSheet(
        title: tr("Rename Simulator"),
        actionTitle: tr("Rename Simulator"),
        systemImage: "pencil",
        explanation: tr(
          "Renaming changes only the simulator’s display name. Its apps, data, runtime, and service profile stay the same."
        ),
        initialName: device.name,
        device: device
      ) { name in
        Task { await model.renameSimulator(device, to: name) }
      }

    case .erase(let devices):
      SimulatorDestructiveSheet(action: .erase, devices: devices) {
        Task { await model.eraseSimulators(devices) }
      }

    case .delete(let devices):
      SimulatorDestructiveSheet(action: .delete, devices: devices) {
        Task { await model.deleteSimulators(devices) }
      }

    case .diskCleanup(let devices, let categories):
      DiskCleanupConfirmationSheet(devices: devices, categories: categories) { device in
        presentAfterSheetDismissal(.clone(device))
      } onConfirm: { categoryIDs in
        Task { await model.cleanDisk(devices, categoryIDs: categoryIDs) }
      }
    }
  }

  private func presentAfterSheetDismissal(_ sheet: SimulatorManagementSheet) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      managementSheet = sheet
    }
  }
}

private struct ToolbarActionLabel: View {
  let title: String
  let systemImage: String

  init(_ title: String, systemImage: String) {
    self.title = title
    self.systemImage = systemImage
  }

  var body: some View {
    // Keep icon + text via SwiftUI. Setting NSToolbar.displayMode at runtime
    // suspends SwiftUI's render transaction when the sidebar is toggled.
    Label(title, systemImage: systemImage)
      .labelStyle(.titleAndIcon)
      .accessibilityLabel(title)
  }
}

private struct CollapsibleToolbarSearch: View {
  @Binding var text: String
  let prompt: String
  @Binding var isExpanded: Bool

  @ViewBuilder
  var body: some View {
    if isExpanded {
      if #available(macOS 26.0, *) {
        searchContent
          .padding(.horizontal, 10)
          .frame(width: 300, height: 32)
      } else {
        searchContent
          .padding(.horizontal, 10)
          .frame(width: 280, height: 30)
          .background(.regularMaterial, in: Capsule())
      }
    } else {
      Button {
        withAnimation(.easeInOut(duration: 0.16)) {
          isExpanded = true
        }
      } label: {
        ToolbarActionLabel(
          tr("Search"),
          systemImage: text.isEmpty ? "magnifyingglass" : "magnifyingglass.circle.fill"
        )
      }
      .help(text.isEmpty ? prompt : tr("%@ — filter active", prompt))
      .accessibilityLabel(text.isEmpty ? prompt : tr("%@ — filter active", prompt))
    }
  }

  private var searchContent: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      AutofocusingToolbarTextField(
        text: $text,
        prompt: prompt,
        onSubmit: {
          if text.isEmpty {
            collapse()
          }
        },
        onCancel: collapse
      )
      .frame(maxWidth: .infinity)

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(tr("Clear search"))
      }

      Button {
        collapse()
      } label: {
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(tr("Collapse search"))
      .accessibilityLabel(tr("Collapse search"))
    }
    .onExitCommand(perform: collapse)
  }

  private func collapse() {
    withAnimation(.easeInOut(duration: 0.16)) {
      isExpanded = false
    }
  }
}

private struct AutofocusingToolbarTextField: NSViewRepresentable {
  @Binding var text: String
  let prompt: String
  let onSubmit: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> AutofocusingTextField {
    let textField = AutofocusingTextField()
    textField.delegate = context.coordinator
    textField.stringValue = text
    textField.placeholderString = prompt
    textField.isBezeled = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.usesSingleLineMode = true
    textField.lineBreakMode = .byTruncatingTail
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textField.setAccessibilityLabel(prompt)
    return textField
  }

  func updateNSView(_ textField: AutofocusingTextField, context: Context) {
    context.coordinator.parent = self
    if textField.stringValue != text {
      textField.stringValue = text
    }
    textField.placeholderString = prompt
    textField.setAccessibilityLabel(prompt)
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: AutofocusingToolbarTextField

    init(parent: AutofocusingToolbarTextField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let textField = notification.object as? NSTextField else { return }
      if parent.text != textField.stringValue {
        parent.text = textField.stringValue
      }
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        parent.onSubmit()
        return true
      }
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        parent.onCancel()
        return true
      }
      return false
    }
  }
}

private final class AutofocusingTextField: NSTextField {
  private var hasRequestedFocus = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil, !hasRequestedFocus else { return }
    hasRequestedFocus = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.window?.makeFirstResponder(self)
    }
  }
}

private struct MetricPill: View {
  let value: String
  let label: String
  let color: Color

  var body: some View {
    HStack(spacing: 7) {
      Text(value)
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundStyle(color)
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(color.opacity(0.1), in: Capsule())
  }
}

private struct ProfileSidebar: View {
  @EnvironmentObject private var model: AppModel
  @Binding var mode: SlimmingMode
  @State private var serviceSearchText = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: 46, height: 46)
        VStack(alignment: .leading, spacing: 2) {
          Text("SimSlim")
            .font(.title2.bold())
          Text(mode == .memory ? tr("Service slimming · reversible") : tr("Disk analysis & cleanup"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(18)

      Picker(tr("Slimming mode"), selection: $mode) {
        ForEach(SlimmingMode.allCases) { option in
          Text(option.localizedName).tag(option)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 16)
      .padding(.bottom, 14)

      Divider()

      ScrollView {
        Group {
          if mode == .memory {
            memoryContent
          } else {
            diskContent
          }
        }
        .padding(16)
      }
    }
    .background(.regularMaterial)
  }

  private var sortedMemoryCategories: [SlimCategory] {
    model.categories.sorted {
      if $0.approxMemoryMB == $1.approxMemoryMB {
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return $0.approxMemoryMB > $1.approxMemoryMB
    }
  }

  private var filteredMemoryCategories: [SlimCategory] {
    let query = serviceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return sortedMemoryCategories }
    return sortedMemoryCategories.filter { category in
      category.name.localizedCaseInsensitiveContains(query)
        || category.description.localizedCaseInsensitiveContains(query)
        || category.downside.localizedCaseInsensitiveContains(query)
        || category.labels.contains {
          $0.localizedCaseInsensitiveContains(query)
        }
        || category.labels.contains {
          category.serviceDescription(for: $0).localizedCaseInsensitiveContains(query)
        }
        || category.alwaysEnabledServices.contains {
          $0.label.localizedCaseInsensitiveContains(query)
            || $0.reason.localizedCaseInsensitiveContains(query)
        }
    }
  }

  private var sortedDiskCategories: [DiskCleanupCategory] {
    model.diskCleanupCategories.filter(\.canClean).sorted {
      let left = model.diskCleanupBytes(for: $0.id) ?? 0
      let right = model.diskCleanupBytes(for: $1.id) ?? 0
      if left == right {
        if $0.canClean != $1.canClean { return $0.canClean }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return left > right
    }
  }

  private var memoryContent: some View {
    VStack(alignment: .leading, spacing: 15) {
      stateLegend

      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(tr("Services to keep"))
            .font(.headline)
          Spacer()
          Button(tr("Full Slim")) { model.resetProfile() }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(
              (model.keptCategoryIDs.isEmpty && model.keptServiceLabels.isEmpty) || model.isBusy)
        }
        Text(
          tr(
            "Sorted by estimated idle memory use. Enable categories your tests need; estimates vary and are not additive."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      SidebarServiceSearch(text: $serviceSearchText)

      VStack(alignment: .leading, spacing: 8) {
        ForEach(filteredMemoryCategories) { category in
          CategoryToggle(
            category: category,
            serviceQuery: serviceSearchText
          )
        }

        if !serviceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && filteredMemoryCategories.isEmpty
        {
          Text(tr("No services match \u{201c}%@\u{201d}", serviceSearchText))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Toggle(tr("Preserve current boot state"), isOn: $model.preserveBootState)
        .font(.subheadline.weight(.medium))
        .disabled(model.isBusy)
      Text(
        tr(
          "A simulator that starts shutdown will return to shutdown after its service profile is changed."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 7) {
        Label(
          tr("Up to %d services will be disabled", model.disabledDaemonCount),
          systemImage: "circle")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)
        Text(
          tr(
            "Core workflow and deadlock-prone daemons are never disabled. HomeKit’s homed stays enabled on watchOS, and the asset service mobileassetd on visionOS."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private var diskContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(tr("Cleanup"))
            .font(.headline)
          Spacer()
          Text(model.selectedDiskCleanupSizeText())
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(model.diskAnalysisCoversSelection ? Color.orange : Color.secondary)
        }
        Text(tr("Updates automatically when your selection changes. Analysis is read-only."))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button {
          Task { await model.analyzeDiskSelection() }
        } label: {
          Label(tr("Re-analyze Selected"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(model.selectionCount == 0 || !model.canStartBatchOnSelection)
        .help(tr("Refresh disk usage for the selected simulators"))
      }

      VStack(alignment: .leading, spacing: 8) {
        ForEach(sortedDiskCategories) { category in
          DiskCleanupCategoryToggle(category: category)
        }
      }

      if model.diskAnalysisCoversSelection {
        VStack(alignment: .leading, spacing: 8) {
          Text(tr("Storage breakdown"))
            .font(.headline)
          Text(tr("Read-only sizes. These files are never selected for cleanup."))
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(model.diskStorageRows) { storage in
            DiskStorageRow(
              storage: storage,
              sizeText: model.diskStorageSizeText(for: storage.id)
            )
          }
        }
      }

      Toggle(tr("Reopen previously booted simulators"), isOn: $model.preserveBootState)
        .font(.subheadline.weight(.medium))
        .disabled(model.isBusy)

      VStack(alignment: .leading, spacing: 7) {
        Text(
          tr(
            "Required Siri assets aren’t offered for deletion — iOS restores them automatically on launch."
          )
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.blue)
        Text(tr("Built-in apps and core OS resources are never modified."))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var stateLegend: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(tr("Service state"))
        .font(.headline)
      HStack(spacing: 13) {
        LegendItem(icon: "circle.fill", label: tr("Stock"))
        LegendItem(icon: "circle.lefthalf.filled", label: tr("Partial"))
        LegendItem(icon: "circle", label: tr("Slim"))
      }
      .foregroundStyle(.secondary)
    }
  }
}

private struct SidebarServiceSearch: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField(tr("Find a service"), text: $text)
        .textFieldStyle(.plain)
        .accessibilityLabel(tr("Find a service"))

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(tr("Clear service search"))
      }
    }
    .padding(.horizontal, 9)
    .frame(height: 29)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
    }
  }
}

private struct DiskCleanupCategoryToggle: View {
  @EnvironmentObject private var model: AppModel
  let category: DiskCleanupCategory

  private var isSelected: Binding<Bool> {
    Binding(
      get: { model.selectedDiskCleanupCategoryIDs.contains(category.id) },
      set: { model.setDiskCleanupCategory(category, selected: $0) }
    )
  }

  private var accentColor: Color {
    category.id == "linguistic-data" ? .blue : .orange
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        VStack(alignment: .leading, spacing: 4) {
          Text(tr(category.name))
            .font(.subheadline.weight(.medium))
          if category.risk != "Lower risk" {
            Text(tr(category.risk).uppercased())
              .font(.system(size: 8, weight: .bold))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
              .foregroundStyle(accentColor)
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(accentColor.opacity(0.1), in: Capsule())
          }
        }

        Label(model.diskCleanupSizeText(for: category.id), systemImage: "internaldrive")
          .font(.caption.weight(.semibold))
          .foregroundStyle(accentColor)

        (Text(tr("Impact: ")).fontWeight(.semibold) + Text(tr(category.downside)))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        (Text(tr("Afterward: ")).fontWeight(.semibold) + Text(tr(category.recovery)))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if !category.canClean {
          Text(tr("Unable to delete — iOS restores automatically on launch."))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if category.canClean {
        Toggle(tr("Remove %@", tr(category.name)), isOn: isSelected)
          .labelsHidden()
          .toggleStyle(.switch)
          .disabled(model.isBusy)
          .padding(.top, 1)
      } else {
        Image(systemName: "lock.fill")
          .foregroundStyle(.secondary)
          .frame(width: 38, height: 24)
          .accessibilityLabel(tr("Deletion unavailable"))
          .padding(.top, 1)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    .help(tr(category.recovery))
  }
}

private struct DiskStorageRow: View {
  let storage: SimulatorDiskStorageMeasurement
  let sizeText: String

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: storage.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 17)

      VStack(alignment: .leading, spacing: 2) {
        Text(tr(storage.name))
          .font(.subheadline.weight(.medium))
        Text(tr(storage.description))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Text(sizeText)
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct LegendItem: View {
  let icon: String
  let label: String

  var body: some View {
    Label(label, systemImage: icon)
      .font(.caption)
  }
}

private struct CategoryToggle: View {
  @EnvironmentObject private var model: AppModel
  let category: SlimCategory
  let serviceQuery: String
  @State private var isExpanded = false

  private var isKeptEnabled: Binding<Bool> {
    Binding(
      get: { model.categoryIsKept(category) },
      set: { model.setCategory(category, keptEnabled: $0) }
    )
  }

  private var showsServices: Bool {
    isExpanded || !normalizedQuery.isEmpty
  }

  private var serviceCount: Int {
    category.labels.count + category.alwaysEnabledServices.count
  }

  private var normalizedQuery: String {
    serviceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var categoryMetadataMatchesQuery: Bool {
    guard !normalizedQuery.isEmpty else { return false }
    return category.name.localizedCaseInsensitiveContains(normalizedQuery)
      || category.description.localizedCaseInsensitiveContains(normalizedQuery)
      || category.downside.localizedCaseInsensitiveContains(normalizedQuery)
  }

  private var visibleLabels: [String] {
    guard !normalizedQuery.isEmpty, !categoryMetadataMatchesQuery else { return category.labels }
    return category.labels.filter {
      $0.localizedCaseInsensitiveContains(normalizedQuery)
        || category.serviceDescription(for: $0).localizedCaseInsensitiveContains(normalizedQuery)
    }
  }

  private var visibleAlwaysEnabledServices: [AlwaysEnabledService] {
    guard !normalizedQuery.isEmpty, !categoryMetadataMatchesQuery else {
      return category.alwaysEnabledServices
    }
    return category.alwaysEnabledServices.filter {
      $0.label.localizedCaseInsensitiveContains(normalizedQuery)
        || $0.reason.localizedCaseInsensitiveContains(normalizedQuery)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Button {
          withAnimation(.easeInOut(duration: 0.16)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: showsServices ? "chevron.down" : "chevron.right")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.secondary)
              .frame(width: 9)

            Text(tr(category.name))
              .font(.subheadline.weight(.medium))
              .fixedSize(horizontal: false, vertical: true)

            Text("\(serviceCount)")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
        }
        .buttonStyle(.plain)
        .help(showsServices ? tr("Hide individual services") : tr("Show individual services"))

        Spacer(minLength: 4)

        Toggle(tr("Keep %@ enabled", tr(category.name)), isOn: isKeptEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
          .disabled(model.isBusy)
          .padding(.top, 1)
          .help(tr("Keep all controllable services in %@ enabled", tr(category.name)))
      }

      Label(category.approximateMemoryText, systemImage: "memorychip")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.1), in: Capsule())
        .help(category.approximateMemoryText)

      (Text(tr("When disabled: ")).fontWeight(.semibold) + Text(tr(category.downside)))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if showsServices {
        Divider()

        VStack(alignment: .leading, spacing: 6) {
          ForEach(visibleLabels, id: \.self) { label in
            ServiceToggle(label: label, category: category)
          }

          ForEach(visibleAlwaysEnabledServices) { service in
            AlwaysEnabledServiceRow(service: service)
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct ServiceToggle: View {
  @EnvironmentObject private var model: AppModel
  let label: String
  let category: SlimCategory

  private var isKeptEnabled: Binding<Bool> {
    Binding(
      get: { model.serviceIsKept(label) },
      set: { model.setService(label, in: category, keptEnabled: $0) }
    )
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "gearshape.2")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 15)

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption.monospaced())
          .lineLimit(2)
          .textSelection(.enabled)
        Text(category.serviceDescription(for: label))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 4)

      Toggle(tr("Keep %@ enabled", label), isOn: isKeptEnabled)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(model.isBusy)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
  }
}

private struct AlwaysEnabledServiceRow: View {
  let service: AlwaysEnabledService

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock.fill")
        .font(.caption)
        .foregroundStyle(.blue)
        .frame(width: 15)

      VStack(alignment: .leading, spacing: 2) {
        Text(service.label)
          .font(.caption.monospaced())
          .lineLimit(2)
          .textSelection(.enabled)
        Text(tr(service.reason))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 4)

      Text(tr("Always on"))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.1), in: Capsule())
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
  }
}

private struct SimulatorRow: View {
  @EnvironmentObject private var model: AppModel
  let device: SimulatorDevice
  let diskCleanupCategories: [DiskCleanupCategory]
  @Binding var managementSheet: SimulatorManagementSheet?

  private var isSelected: Bool { model.selectedUDIDs.contains(device.udid) }
  private var operation: String? { model.activeOperations[device.udid] }

  var body: some View {
    VStack(spacing: 7) {
      HStack(spacing: 12) {
        Button {
          model.toggleSelection(device.udid)
        } label: {
          Image(systemName: isSelected ? "checkmark.square.fill" : "square")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy(device))

        HStack(spacing: 10) {
          Image(systemName: device.deviceSymbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(device.isBooted ? Color.blue : Color.secondary)
            .frame(width: 35, height: 35)
            .background(
              (device.isBooted ? Color.blue : Color.secondary).opacity(0.09),
              in: RoundedRectangle(cornerRadius: 9))
          VStack(alignment: .leading, spacing: 2) {
            Text(device.name)
              .font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
              Text(device.udid)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .textSelection(.enabled)

              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.udid, forType: .string)
              } label: {
                Image(systemName: "doc.on.doc")
                  .font(.system(size: 9, weight: .medium))
                  .frame(width: 14, height: 14)
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help(tr("Copy UDID"))
              .accessibilityLabel(tr("Copy UDID for %@", device.name))
            }
          }
        }
        .frame(minWidth: 255, maxWidth: .infinity, alignment: .leading)

        Text(device.runtimeName)
          .font(.subheadline)
          .frame(width: 74, alignment: .leading)

        BootStateView(isBooted: device.isBooted)
          .frame(width: 86, alignment: .leading)

        ServiceStateView(
          state: model.slimState(for: device),
          isCached: model.stateIsCached(for: device),
          operation: operation
        )
        .frame(width: 150, alignment: .leading)

        Text(model.diskSizeText(for: device))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(model.diskSizes[device.udid] == nil ? .tertiary : .secondary)
          .frame(width: 105, alignment: .leading)
          .help(tr("Current allocated size of this simulator on disk"))

        Group {
          if let measurement = model.measurements[device.udid] {
            Text(measurement.memoryText)
              .font(.subheadline.monospacedDigit())
          } else {
            Text("—")
              .foregroundStyle(.tertiary)
          }
        }
        .frame(width: 82, alignment: .leading)

        Menu {
          Section(tr("Power")) {
            if device.isBooted {
              Button {
                Task { await model.shutdownSimulator(device) }
              } label: {
                Label(tr("Shut Down Simulator"), systemImage: "stop.fill")
              }
            } else {
              Button {
                Task { await model.bootSimulator(device) }
              } label: {
                Label(tr("Boot Simulator"), systemImage: "play.fill")
              }
            }

            Button {
              Task { await model.openSimulator(device) }
            } label: {
              Label(tr("Open Simulator"), systemImage: "macwindow")
            }
            .disabled(model.isBusy(device))
          }

          Section(tr("Service Profile")) {
            Button {
              managementSheet = .slimmingRecommendation([device])
            } label: {
              Label(tr("Slim Simulator"), systemImage: "minus.circle")
            }
            .disabled(model.isBatchRunning)

            Button {
              Task { await model.restoreOriginalServices(for: device) }
            } label: {
              Label(tr("Unslim Simulator"), systemImage: "plus.circle")
            }
            .disabled(model.isBatchRunning)
          }

          Section(tr("Disk Space")) {
            Button(role: .destructive) {
              managementSheet = .diskCleanup([device], diskCleanupCategories)
            } label: {
              Label(tr("Clean Disk Data"), systemImage: "externaldrive.badge.xmark")
            }
            .disabled(!model.canCleanDisk([device]) || model.isBatchRunning)
          }

          Section(tr("Simulator")) {
            Button {
              managementSheet = .clone(device)
            } label: {
              Label(tr("Clone Simulator"), systemImage: "plus.square.on.square")
            }

            Button {
              managementSheet = .rename(device)
            } label: {
              Label(tr("Rename Simulator"), systemImage: "pencil")
            }
          }

          Section(tr("Finder")) {
            Button {
              openInFinder(simulatorDirectoryURL)
            } label: {
              Label(tr("Show Simulator in Finder"), systemImage: "folder")
            }

            Button {
              openInFinder(appDataContainersURL)
            } label: {
              Label(
                tr("Show App Data Containers in Finder"), systemImage: "folder.badge.gearshape")
            }
          }

          Section(tr("Status")) {
            Button {
              Task { await model.refresh() }
            } label: {
              Label(tr("Refresh Simulator Status"), systemImage: "arrow.clockwise")
            }

            Button {
              Task { await model.measure(device) }
            } label: {
              Label(tr("Refresh RAM"), systemImage: "memorychip")
            }
            .disabled(!device.isBooted)
          }

          Section(tr("Selection")) {
            Button(isSelected ? tr("Deselect Simulator") : tr("Select Simulator")) {
              model.toggleSelection(device.udid)
            }
          }

          Section(tr("Destructive Actions")) {
            Button(role: .destructive) {
              managementSheet = .erase([device])
            } label: {
              Label(tr("Erase Simulator"), systemImage: "eraser")
            }
            .disabled(model.isBatchRunning)

            Button(role: .destructive) {
              managementSheet = .delete([device])
            } label: {
              Label(tr("Delete Simulator"), systemImage: "trash")
            }
            .disabled(model.isBatchRunning)
          }
        } label: {
          Image(systemName: "ellipsis")
            .frame(width: 20)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isBusy(device))
        .frame(width: 28)
      }

      if let operation {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(tr(operation))
          Spacer()
          Text(tr("Booting and rebooting can take a few minutes"))
            .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 48)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 9)
    .background(isSelected ? Color.accentColor.opacity(0.075) : Color.clear)
    .animation(.easeInOut(duration: 0.16), value: isSelected)
    .animation(.easeInOut(duration: 0.16), value: operation)
  }

  private var simulatorDirectoryURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
      .appendingPathComponent(device.udid, isDirectory: true)
  }

  private var appDataContainersURL: URL {
    simulatorDirectoryURL
      .appendingPathComponent("data", isDirectory: true)
      .appendingPathComponent("Containers/Data/Application", isDirectory: true)
  }

  private func openInFinder(_ url: URL) {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      model.presentedError = PresentedError(
        message: tr("The directory for %@ does not exist at %@.", device.name, url.path))
      return
    }
    guard NSWorkspace.shared.open(url) else {
      model.presentedError = PresentedError(
        message: tr("Finder could not open %@.", url.path))
      return
    }
  }
}

private struct BootStateView: View {
  let isBooted: Bool

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(isBooted ? Color.green : Color.gray)
        .frame(width: 7, height: 7)
      Text(isBooted ? tr("Booted") : tr("Shutdown"))
        .font(.subheadline)
        .foregroundStyle(isBooted ? Color.primary : Color.secondary)
    }
  }
}

private struct ServiceStateView: View {
  let state: ServiceSlimState
  let isCached: Bool
  let operation: String?

  var body: some View {
    HStack(spacing: 8) {
      if operation != nil {
        ProgressView()
          .controlSize(.small)
          .frame(width: 17)
      } else {
        Image(systemName: state.systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 17)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(operation == nil ? state.title : tr("Changing…"))
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        if isCached && operation == nil {
          Text(tr("last verified"))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
      }
    }
    .help(
      isCached
        ? tr(
          "Last verified while booted; launchd state cannot be queried live while this simulator is shutdown."
        )
        : state.title
    )
    .accessibilityLabel(tr("Service slimming: %@", state.title))
  }

}

private struct ActivityPanel: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label(tr("Activity"), systemImage: "text.alignleft")
          .font(.subheadline.weight(.semibold))
        Spacer()
        if !model.activity.isEmpty {
          Button(tr("Clear")) { model.clearActivity() }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)

      if model.activity.isEmpty {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle")
            .foregroundStyle(.green)
          Text(tr("Ready. Select simulators, then choose an action from the toolbar."))
            .foregroundStyle(.secondary)
          Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(model.activity.prefix(7)) { entry in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon(for: entry.level))
                  .foregroundStyle(color(for: entry.level))
                Text(entry.date.formatted(date: .omitted, time: .standard))
                  .monospacedDigit()
                  .foregroundStyle(.tertiary)
                Text(entry.message)
                  .textSelection(.enabled)
                Spacer()
              }
              .font(.caption)
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 9)
        }
        .frame(maxHeight: 95)
      }
    }
    .frame(height: model.activity.isEmpty ? 64 : 122, alignment: .top)
    .background(.bar)
  }

  private func icon(for level: ActivityEntry.Level) -> String {
    switch level {
    case .info: return "arrow.right.circle"
    case .success: return "checkmark.circle.fill"
    case .failure: return "exclamationmark.triangle.fill"
    }
  }

  private func color(for level: ActivityEntry.Level) -> Color {
    switch level {
    case .info: return .blue
    case .success: return .green
    case .failure: return .red
    }
  }
}

private struct LanguageMenu: View {
  @EnvironmentObject private var localization: Localization

  var body: some View {
    Menu {
      ForEach(AppLanguage.allCases) { language in
        Button {
          localization.selectLanguage(language)
        } label: {
          if language == localization.selectedLanguage {
            Label(language.displayName, systemImage: "checkmark")
          } else {
            Text(language.displayName)
          }
        }
      }
      if localization.selectedLanguage != localization.language {
        Divider()
        Text(tr("Restart to apply"))
      }
    } label: {
      Label(tr("Language"), systemImage: "globe")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel(tr("Language"))
  }
}

/// `ContentUnavailableView` is macOS 14 and newer; macOS 13 gets an equivalent
/// placeholder with the same symbol, title, and description.
private struct SimulatorEmptyState: View {
  let title: String
  let systemImage: String
  let description: String

  @ViewBuilder
  var body: some View {
    if #available(macOS 14.0, *) {
      ContentUnavailableView(
        title,
        systemImage: systemImage,
        description: Text(description)
      )
    } else {
      VStack(spacing: 9) {
        Image(systemName: systemImage)
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.tertiary)
          .padding(.bottom, 2)

        Text(title)
          .font(.title2.weight(.semibold))

        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
    }
  }
}
