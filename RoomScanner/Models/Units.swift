import Foundation

enum LengthUnit: String, CaseIterable, Identifiable {
    case millimeters, centimeters, meters, inches

    var id: String { rawValue }

    var label: String {
        switch self {
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .meters: return "m"
        case .inches: return "in"
        }
    }

    /// How many of this unit are in one meter.
    var perMeter: Double {
        switch self {
        case .millimeters: return 1000
        case .centimeters: return 100
        case .meters: return 1
        case .inches: return 1 / 0.0254
        }
    }

    /// DXF $INSUNITS code.
    var dxfCode: Int {
        switch self {
        case .millimeters: return 4
        case .centimeters: return 5
        case .meters: return 6
        case .inches: return 1
        }
    }

    /// Easy-to-read text, e.g. "3.214 m" or "126.50 in (10' 6.5")".
    func format(meters: Double) -> String {
        let v = meters * perMeter
        switch self {
        case .millimeters: return String(format: "%.0f mm", v)
        case .centimeters: return String(format: "%.1f cm", v)
        case .meters: return String(format: "%.3f m", v)
        case .inches:
            let feet = Int(v / 12)
            let rest = v - Double(feet) * 12
            return feet > 0
                ? String(format: "%.2f in (%ld' %.1f\")", v, feet, rest)
                : String(format: "%.2f in", v)
        }
    }

    func formatArea(squareMeters: Double) -> String {
        switch self {
        case .inches: return String(format: "%.1f sq ft", squareMeters * 10.7639)
        default: return String(format: "%.2f m²", squareMeters)
        }
    }
}
