import CoreGraphics

/// Keep Overview readable on wide screens without squeezing compact windows.
public enum DashboardContentGeometry {
    public static let maximumWidth: CGFloat = 1_100

    public static func width(available: CGFloat) -> CGFloat {
        min(maximumWidth, max(0, available))
    }

    public static func margin(available: CGFloat) -> CGFloat {
        max(0, (available - width(available: available)) / 2)
    }
}
