import Foundation

/// The Health page's two numbers. They live beside `K`'s others by name, and in a file of their own because
/// `Constants.swift` is a file of the safety layer (`scripts/safety-gates.sh`): these reach nothing that
/// can hold up a click, and a change to them owes nobody a drill.
extension K {
    /// How far back the Health page counts crash reports. A week covers the gap between two weekly update
    /// checks, and a crash older than that has either been fixed by a release or been seen again since.
    public static let healthCrashWindow: TimeInterval = 7 * 24 * 60 * 60

    /// The shortest time Check Again shows its spinner. Most checks answer in a few milliseconds, and a
    /// spinner that goes before it can be seen reads as a button that did nothing; half a second is seen and
    /// does not keep anyone waiting.
    public static let healthMinimumBusy: TimeInterval = 0.5
}
