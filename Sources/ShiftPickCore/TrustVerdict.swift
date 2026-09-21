import Foundation

/// What a live question about the Accessibility grant came back with.
///
/// **`unknown` is not `revoked`.** A process that did not answer in time says nothing about the grant, and
/// treating it as a loss would send the user back to the onboarding wizard because the Dock was busy. It is
/// not `trusted` either: nothing is armed on an answer that never came.
public enum TrustVerdict: Equatable, Sendable {
    /// Another process answered a real Accessibility request just now.
    case trusted
    /// The system said the grant is gone: `AXIsProcessTrusted()` answered false, or a request came back
    /// `apiDisabled`.
    case revoked
    /// Nobody answered in time, or the process that was asked has gone.
    case unknown
}
