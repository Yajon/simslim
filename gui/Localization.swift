import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case english = "en"
  case chinese = "zh-Hans"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .english: return "English"
    case .chinese: return "简体中文"
    }
  }
}

/// macOS localizes `NSToolbar` labels through `NSToolbarItem.setLabel:`, which
/// aborts inside `NSToolbarItemViewer._itemChanged` when the relabel lands in an
/// animated transaction — exactly what happens right after picking an item from
/// a toolbar menu. Switching languages in place therefore crashes the app, so
/// the choice is persisted instead and applied on the next launch: the loaded
/// table keeps serving the current language, and the app offers to relaunch.
final class Localization: ObservableObject {
  static let shared = Localization()
  private static let languageKey = "appLanguage"
  private static let appleLanguagesKey = "AppleLanguages"

  /// The language the running UI was built with. Never changes in place.
  let language: AppLanguage
  /// The user's latest choice, applied the next time the app launches.
  @Published private(set) var selectedLanguage: AppLanguage
  @Published var showsRestartPrompt = false

  private let table: [String: String]

  private init() {
    let active = Self.storedLanguage() ?? Self.systemLanguage()
    language = active
    selectedLanguage = active
    table = Self.loadTable(for: active)
  }

  func selectLanguage(_ newLanguage: AppLanguage) {
    guard newLanguage != selectedLanguage else { return }
    selectedLanguage = newLanguage
    UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.languageKey)
    UserDefaults.standard.set([newLanguage.rawValue], forKey: Self.appleLanguagesKey)
    guard newLanguage != language else { return }
    // The menu that triggered this call is still tracking; hop to the next
    // runloop turn so the alert is presented after it dismisses.
    DispatchQueue.main.async { [weak self] in
      self?.showsRestartPrompt = true
    }
  }

  func relaunch() {
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else {
      NSApp.terminate(nil)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }

  func string(_ key: String) -> String {
    table[key] ?? key
  }

  func string(_ key: String, _ arguments: [CVarArg]) -> String {
    String(format: table[key] ?? key, arguments: arguments)
  }

  private static func storedLanguage() -> AppLanguage? {
    UserDefaults.standard.string(forKey: languageKey).flatMap(AppLanguage.init(rawValue:))
  }

  private static func systemLanguage() -> AppLanguage {
    Bundle.main.preferredLocalizations.contains(AppLanguage.chinese.rawValue) ? .chinese : .english
  }

  private static func loadTable(for language: AppLanguage) -> [String: String] {
    guard
      let path = Bundle.main.path(
        forResource: "Localizable", ofType: "strings", inDirectory: nil,
        forLocalization: language.rawValue)
    else { return [:] }
    return NSDictionary(contentsOfFile: path) as? [String: String] ?? [:]
  }
}

/// Returns the localized form of an English source string.
func tr(_ key: String) -> String {
  Localization.shared.string(key)
}

/// Returns the localized form of an English format string.
func tr(_ key: String, _ arguments: CVarArg...) -> String {
  Localization.shared.string(key, arguments)
}
