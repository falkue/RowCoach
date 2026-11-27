import Foundation

/// Liest die Figur- und Bootsteile im eigenen Binärformat von tools/avatars/build.py (`*.rcmesh`).
/// Die App baut daraus die Meshes selbst (`MeshDescriptor`) und hängt nicht davon ab, wie RealityKit USD-Prims
/// benennt oder zusammenfasst (Mac-Test 27.11.2026: fremde Haarteile unter Kopftuch und Patka).
///
/// Aufbau: 8 Byte „RCMESH01“, UInt32 LE Länge des JSON-Kopfs, JSON-Kopf, Datenblock (Float32 LE Punkte und Normalen,
/// optional UV, UInt32 LE Dreiecks-Indizes; Versätze im Kopf relativ zum Datenblock).
public enum AvatarMeshFile {
    public struct Mesh: Sendable {
        public var name: String
        public var frame: String
        public var group: String
        public var positions: [SIMD3<Float>]
        public var normals: [SIMD3<Float>]
        public var uv: [SIMD2<Float>]?
        public var indices: [UInt32]
    }

    public enum ParseError: Error, Equatable {
        case badMagic
        case badHeader
        case outOfRange(String)
    }

    private struct Header: Decodable {
        struct Part: Decodable {
            var name: String
            var frame: String
            var group: String
            var vertices: Int
            var indices: Int
            var positions: Int
            var normals: Int
            var uv: Int?
            var indexOffset: Int
        }
        var version: Int
        var parts: [Part]
    }

    public static let magic = Array("RCMESH01".utf8)

    public static func parse(_ data: Data) throws -> [Mesh] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, Array(bytes[0..<8]) == magic else { throw ParseError.badMagic }
        let headLen = Int(UInt32(bytes[8]) | UInt32(bytes[9]) << 8 | UInt32(bytes[10]) << 16 | UInt32(bytes[11]) << 24)
        guard 12 + headLen <= bytes.count,
              let header = try? JSONDecoder().decode(Header.self, from: Data(bytes[12..<(12 + headLen)])) else {
            throw ParseError.badHeader
        }
        let base = 12 + headLen
        func floats(_ offset: Int, _ count: Int, _ name: String) throws -> [Float] {
            let start = base + offset, end = start + count * 4
            guard offset >= 0, end <= bytes.count else { throw ParseError.outOfRange(name) }
            var out = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let j = start + i * 4
                let bits = UInt32(bytes[j]) | UInt32(bytes[j + 1]) << 8 | UInt32(bytes[j + 2]) << 16 | UInt32(bytes[j + 3]) << 24
                out[i] = Float(bitPattern: bits)
            }
            return out
        }
        func uints(_ offset: Int, _ count: Int, _ name: String) throws -> [UInt32] {
            let start = base + offset, end = start + count * 4
            guard offset >= 0, end <= bytes.count else { throw ParseError.outOfRange(name) }
            var out = [UInt32](repeating: 0, count: count)
            for i in 0..<count {
                let j = start + i * 4
                out[i] = UInt32(bytes[j]) | UInt32(bytes[j + 1]) << 8 | UInt32(bytes[j + 2]) << 16 | UInt32(bytes[j + 3]) << 24
            }
            return out
        }
        return try header.parts.map { p in
            let pos = try floats(p.positions, p.vertices * 3, p.name)
            let nrm = try floats(p.normals, p.vertices * 3, p.name)
            let uv = try p.uv.map { try floats($0, p.vertices * 2, p.name) }
            let idx = try uints(p.indexOffset, p.indices, p.name)
            guard idx.allSatisfy({ Int($0) < p.vertices }) else { throw ParseError.outOfRange(p.name) }
            return Mesh(name: p.name, frame: p.frame, group: p.group,
                        positions: stride(from: 0, to: pos.count, by: 3).map { SIMD3(pos[$0], pos[$0 + 1], pos[$0 + 2]) },
                        normals: stride(from: 0, to: nrm.count, by: 3).map { SIMD3(nrm[$0], nrm[$0 + 1], nrm[$0 + 2]) },
                        uv: uv.map { u in stride(from: 0, to: u.count, by: 2).map { SIMD2(u[$0], u[$0 + 1]) } },
                        indices: idx)
        }
    }
}
