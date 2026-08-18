import Foundation
import SwiftUI

public struct LightStaffSeat: Identifiable, Hashable {
    public let staff: LightStaff
    public let seatNumber: Int
    public let legacySlot: Int?

    public var id: String {
        "\(staff.rawValue)-seat-\(seatNumber)"
    }

    public var shortLabel: String {
        "S\(seatNumber)"
    }

    public var displayLabel: String {
        "\(staff.label) Seat \(seatNumber)"
    }

    public var routingLabel: String {
        if let legacySlot {
            return "\(staff.label) · Seat \(seatNumber) · Slot \(legacySlot)"
        }
        return "\(staff.label) · Seat \(seatNumber)"
    }
}

public enum StageConsoleLayout {
    public static let seatsPerStaff = 6

    public static var allSeats: [LightStaffSeat] {
        LightStaff.stageOrder.flatMap(\.seats)
    }

    public static var routeableSeats: [LightStaffSeat] {
        allSeats.filter { $0.legacySlot != nil }
    }

    public static func seat(for legacySlot: Int) -> LightStaffSeat? {
        routeableSeats.first { $0.legacySlot == legacySlot }
    }
}

public extension LightStaff {
    var accentColor: Color {
        switch self {
        case .sopranoL1: return .slotGreen
        case .sopranoL2: return .hotMagenta
        case .tenorL: return .slotYellow
        case .bassL: return .lightRose
        case .altoL2: return .brightRed
        case .altoL1: return .royalBlue
        }
    }

    var legacySlots: [Int] {
        switch self {
        case .sopranoL1:
            return Array(1...6)
        case .sopranoL2:
            return Array(7...12)
        case .tenorL:
            return Array(13...18)
        case .bassL:
            return Array(19...24)
        case .altoL2:
            return Array(25...30)
        case .altoL1:
            return Array(31...36)
        }
    }

    var seats: [LightStaffSeat] {
        (1...StageConsoleLayout.seatsPerStaff).map { seatIndex in
            LightStaffSeat(
                staff: self,
                seatNumber: seatIndex,
                legacySlot: legacySlots.indices.contains(seatIndex - 1) ? legacySlots[seatIndex - 1] : nil
            )
        }
    }

    var routedSeatCount: Int {
        StageConsoleLayout.seatsPerStaff
    }
}
