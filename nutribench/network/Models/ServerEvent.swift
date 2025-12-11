//
//  ServerEvent.swift
//  nutribench
//

import Foundation

struct ServerEvent: Decodable {
    let user_id: String
    let event_id: String?
    let event_type: String

    let timestampISO: String?
    let timestamp: String?

    let details: [String: AnyDecodable]?
}

