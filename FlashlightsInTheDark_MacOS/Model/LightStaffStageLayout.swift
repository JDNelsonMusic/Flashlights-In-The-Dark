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
            return "\(staff.label) · Seat \(seatNumber) · Legacy \(legacySlot)"
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
            return [16, 29, 44]
        case .sopranoL2:
            return [12, 24, 25, 23, 38, 51]
        case .tenorL:
            return [7, 19, 34]
        case .bassL:
            return [9, 20, 21, 3, 4, 18]
        case .altoL2:
            return [1, 14, 15, 40, 53, 54]
        case .altoL1:
            return [27, 41, 42]
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
        legacySlots.count
    }
}
