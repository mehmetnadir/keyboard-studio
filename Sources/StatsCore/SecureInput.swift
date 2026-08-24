import Carbon.HIToolbox
import Foundation

/// Whether macOS is currently protecting keyboard input.
///
/// When an app enables secure event input — password fields in AppKit, Safari,
/// Chrome and Firefox all do — the system stops delivering keyboard events to
/// every observer on the machine. Nothing here has to *choose* to ignore your
/// password: macOS refuses to hand it over.
///
/// Counting is skipped while this is on, and the state is surfaced in the UI,
/// so "we cannot see what you type in password fields" is something you can
/// watch happen rather than take on trust.
///
/// Caveat worth stating plainly: the protection only covers fields whose app
/// opts in. A custom-drawn text field in some app may not, so this is a very
/// strong guarantee rather than an absolute one.
public enum SecureInput {
  public static var isActive: Bool {
    IsSecureEventInputEnabled()
  }
}
