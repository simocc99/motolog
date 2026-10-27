import Foundation
import CoreLocation

struct TrackPoint: Codable {
    var lat: Double
    var lon: Double
    var alt: Double
    var speed: Double      // m/s
    var time: Date
    var lean: Double       // gradi, negativo = sinistra
    var g: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct Ride: Codable, Identifiable {
    var id = UUID()
    var name: String
    var start: Date
    var end: Date
    var bikeID: UUID?
    var distance: Double = 0          // metri
    var movingTime: TimeInterval = 0
    var elapsed: TimeInterval = 0
    var maxSpeed: Double = 0          // m/s
    var elevationGain: Double = 0     // metri
    var maxLeanLeft: Double = 0
    var maxLeanRight: Double = 0
    var maxG: Double = 0
    var rating: Int = 0
    var notes: String = ""
    var points: [TrackPoint] = []

    var avgSpeed: Double { movingTime > 0 ? distance / movingTime : 0 }
    var stoppedTime: TimeInterval { max(0, elapsed - movingTime) }
    var maxAltitude: Double { points.map(\.alt).max() ?? 0 }
    var minAltitude: Double { points.map(\.alt).min() ?? 0 }
    var maxLean: Double { max(maxLeanLeft, maxLeanRight) }

    static func defaultName(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let part: String
        switch h {
        case 5..<12: part = "mattutino"
        case 12..<18: part = "pomeridiano"
        case 18..<23: part = "serale"
        default: part = "notturno"
        }
        return "Giro \(part)"
    }
}

struct Bike: Codable, Identifiable {
    var id = UUID()
    var name: String
    var brand: String = ""
    var year: Int = 0
    var initialKm: Double = 0
}

struct MaintenanceItem: Codable, Identifiable {
    var id = UUID()
    var bikeID: UUID
    var title: String
    var intervalKm: Double
    var lastDoneKm: Double
}

struct FuelEntry: Codable, Identifiable {
    var id = UUID()
    var bikeID: UUID
    var date: Date
    var liters: Double
    var cost: Double
    var odometerKm: Double
}

struct Deadline: Codable, Identifiable {
    var id = UUID()
    var bikeID: UUID?
    var title: String
    var date: Date
}
