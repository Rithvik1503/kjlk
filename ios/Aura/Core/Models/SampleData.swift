import Foundation

/// Plausible fake data for SwiftUI previews, so every component can be worked on without a
/// device or a network. Never referenced from a code path the shipping app takes.
extension Reading {
    /// A day of readings shaped like a real room: CO₂ climbing while it's occupied, light
    /// following the sun, temperature drifting up in the afternoon.
    static func sampleSeries(hours: Int = 24, every minutes: Int = 5) -> [Reading] {
        let now = Date()
        let steps = max(1, hours * 60 / minutes)
        let calendar = Calendar.current

        return (0..<steps).map { step in
            let date = now.addingTimeInterval(-Double(steps - step) * Double(minutes) * 60)
            let hourOfDay = Double(calendar.component(.hour, from: date))
                + Double(calendar.component(.minute, from: date)) / 60

            // Occupancy curve: low overnight, two peaks around the working day.
            let morning = exp(-pow(hourOfDay - 10, 2) / 8)
            let evening = exp(-pow(hourOfDay - 20, 2) / 10)
            let occupancy = max(morning, evening)

            let wobble = sin(Double(step) / 3.1) * 18 + sin(Double(step) / 11.7) * 26
            let co2 = 470 + occupancy * 780 + wobble

            // Daylight: zero at night, peaking early afternoon.
            let daylight = max(0, sin((hourOfDay - 6.5) / 12 * .pi))
            let lamps = (hourOfDay > 18 || hourOfDay < 7) ? 60.0 : 0
            let light = daylight * 620 + lamps + Double.random(in: -12...12)

            let temperature = 20.6 + daylight * 2.4 + occupancy * 0.9 + sin(Double(step) / 7) * 0.2
            let humidity = 52 - daylight * 7 + occupancy * 4 + sin(Double(step) / 5.3) * 1.8

            return Reading(
                id: Int64(step),
                deviceID: "esp32-room-1",
                recordedAt: date,
                co2: max(410, co2),
                temperature: temperature,
                humidity: humidity.clamped(to: 15...90),
                light: max(0, light)
            )
        }
    }
}
