import Foundation

/// The size the console opens at.
///
/// It used to be more than that. The window was aspect-locked to this ratio and
/// capped at this size, so it was "the console's one size" and every surface was
/// composed against it. Both constraints are gone — the window resizes freely on
/// both axes, with floors from `ConsoleLayout` and no ceiling — so this is a
/// starting size again, which is all a Mac window's default ever is.
public enum DashboardWindowGeometry {
    /// Chosen so the full arrangement fits at once, rather than trading columns
    /// off against each other: 224 sidebar + 562 module + 320 inspector + 420
    /// tool panel + 34 rail. At the old 1240 the same set overflowed by ~280pt,
    /// which is why revealing a tool had to hide the inspector.
    ///
    /// `ConsoleLayoutTests` checks it clears both floors, which is now the only
    /// thing that has to be true of it.
    public static let defaultContentSize = CGSize(width: 1_560, height: 900)
}
