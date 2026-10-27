import Foundation

enum GPX {
    static func string(for ride: Ride) -> String {
        let iso = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="MotoLog" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(ride.name))</name><time>\(iso.string(from: ride.start))</time></metadata>
          <trk><name>\(escape(ride.name))</name><trkseg>

        """
        for p in ride.points {
            out += "    <trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(String(format: "%.1f", p.alt))</ele><time>\(iso.string(from: p.time))</time></trkpt>\n"
        }
        out += "  </trkseg></trk>\n</gpx>\n"
        return out
    }

    static func fileURL(for ride: Ride) -> URL? {
        let safe = ride.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe) \(df.string(from: ride.start)).gpx")
        do {
            try string(for: ride).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
