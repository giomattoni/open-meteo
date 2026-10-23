import Foundation

/**
 GeoJSON Polygon or MultiPolygon in WGS84 (longitude, latitude), alone or inside a Feature.

 A point is inside if an odd number of ring edges lie west of it (even-odd rule), so holes need no special case.
 Like `BoundingBoxWGS84`, the lower bound is inside and the upper bound is outside.
 Polygons must not overlap or cross the date line. Callers ask row by row, so the crossings of the latest latitude are cached.
 */
struct SyncPolygon: Sendable {
    private struct Edge: Sendable {
        let lon0, lat0, lon1, lat1: Double
    }

    private let edges: [Edge]
    private var rowLatitude: Double?
    private var rowCrossings = [Double]()

    init(geoJson: Data) throws {
        let polygons = try geoJson.decodeJson(as: GeoJson.self).polygons
        var edges = [Edge]()
        for ring in polygons.joined() {
            guard ring.count >= 4, ring.allSatisfy({ $0.count >= 2 }) else {
                throw ForecastApiError.generic(message: "A polygon ring needs at least four positions")
            }
            for (a, b) in zip(ring, ring.dropFirst()) {
                edges.append(Edge(lon0: a[0], lat0: a[1], lon1: b[0], lat1: b[1]))
            }
        }
        guard !edges.isEmpty else {
            throw ForecastApiError.generic(message: "No polygon found")
        }
        self.edges = edges
    }

    mutating func contains(latitude lat: Double, longitude lon: Double) -> Bool {
        if rowLatitude != lat {
            rowLatitude = lat
            rowCrossings = edges.compactMap { e -> Double? in
                guard (e.lat0 > lat) != (e.lat1 > lat) else {
                    return nil
                }
                return e.lon0 + (lat - e.lat0) * (e.lon1 - e.lon0) / (e.lat1 - e.lat0)
            }
        }
        return rowCrossings.count(where: { $0 <= lon }) % 2 == 1
    }
}

/// Only the parts of GeoJSON needed for polygons
private struct GeoJson: Decodable {
    /// Polygons, each a list of rings, each a list of [longitude, latitude] positions
    let polygons: [[[[Double]]]]

    enum CodingKeys: String, CodingKey {
        case type, coordinates, geometry
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "Polygon":
            polygons = [try container.decode([[[Double]]].self, forKey: .coordinates)]
        case "MultiPolygon":
            polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
        case "Feature":
            polygons = try container.decode(GeoJson.self, forKey: .geometry).polygons
        case let type:
            throw ForecastApiError.generic(message: "GeoJSON type \(type) is not a polygon")
        }
    }
}
