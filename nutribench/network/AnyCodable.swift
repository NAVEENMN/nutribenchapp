//
//  AnyCodable.swift
//  nutribench
//

import Foundation

struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let v = try? c.decode(Bool.self) {
            value = v; return
        }
        if let v = try? c.decode(Double.self) {
            value = v; return
        }
        if let v = try? c.decode(Int.self) {
            value = v; return
        }
        if let v = try? c.decode(String.self) {
            value = v; return
        }
        if let v = try? c.decode([String: AnyDecodable].self) {
            value = v.mapValues(\.value); return
        }
        if let v = try? c.decode([AnyDecodable].self) {
            value = v.map(\.value); return
        }
        value = NSNull()
    }
}

extension Dictionary where Key == String, Value == AnyDecodable {
    func decode<T: Decodable>(to: T.Type) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: self.mapValues(\.value)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ v: T) { _encode = v.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
