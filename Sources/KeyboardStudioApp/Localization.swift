import Foundation
import SwiftUI

/// App language, independent of the system setting.
///
/// macOS resolves `LocalizedStringKey` against the app's preferred languages,
/// which are fixed at launch — so a change here takes effect on next start.
enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english = "en"
  case turkish = "tr"

  var id: String { rawValue }

  var label: LocalizedStringKey {
    switch self {
    case .system: "menu.language.system"
    case .english: "menu.language.english"
    case .turkish: "menu.language.turkish"
    }
  }

  static let preferenceKey = "app.language"

  static var current: AppLanguage {
    guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
      let language = AppLanguage(rawValue: raw)
    else { return .system }
    return language
  }

  /// Persists the choice through `AppleLanguages`, which is what macOS reads
  /// when it builds the bundle's language list at launch.
  static func apply(_ language: AppLanguage) {
    let defaults = UserDefaults.standard
    defaults.set(language.rawValue, forKey: preferenceKey)
    switch language {
    case .system:
      defaults.removeObject(forKey: "AppleLanguages")
    case .english, .turkish:
      defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
  }
}

extension String {
  /// Localized lookup for strings built at runtime (formatted counts, etc.).
  var localized: String {
    Bundle.module.localizedString(forKey: self, value: nil, table: nil)
  }

  func localized(_ arguments: any CVarArg...) -> String {
    String(format: localized, arguments: arguments)
  }
}
