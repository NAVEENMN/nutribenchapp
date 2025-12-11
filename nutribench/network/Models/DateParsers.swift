//
//  DateParsers.swift
//  nutribench
//

import Foundation

enum DateParsers {
    static func parseServerTimestamp(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }

        // 1) ISO8601 with fractional seconds
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }

        // 2) ISO8601 without fractional seconds
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }

        // 3) Common Mongo/Python string patterns
        let patterns = [
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", // microseconds + tz
            "yyyy-MM-dd HH:mm:ss.SSSXXXXX",    // millis + tz
            "yyyy-MM-dd HH:mm:ssXXXXX",        // no fraction + tz
            "yyyy-MM-dd HH:mm:ss.SSSSSS",      // microseconds, no tz
            "yyyy-MM-dd HH:mm:ss.SSS",         // millis, no tz
            "yyyy-MM-dd HH:mm:ss"              // seconds, no tz
        ]

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for pat in patterns {
            f.timeZone = pat.hasSuffix("XXXXX")
                ? TimeZone(secondsFromGMT: 0)
                : TimeZone.current
            f.dateFormat = pat
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

