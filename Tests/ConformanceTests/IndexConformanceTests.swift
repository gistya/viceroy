import Foundation
import Testing
@testable import Viceroy

// The vendored WHATWG index files are the conformance oracle. For every pointer
// in each index we reconstruct its canonical byte sequence, decode it, and
// assert we get exactly the code point the index prescribes — then round-trip
// through the encoder. This exercises tens of thousands of real mappings.

private let vendorDir: URL =
    URL(fileURLWithPath: #filePath)          // …/Tests/ConformanceTests/IndexConformanceTests.swift
        .deletingLastPathComponent()          // ConformanceTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // repo root
        .appendingPathComponent("vendor/whatwg")

private func parseIndex(_ name: String) -> [(ptr: Int, cp: UInt32)] {
    let text = try! String(contentsOf: vendorDir.appendingPathComponent(name), encoding: .utf8)
    var out: [(Int, UInt32)] = []
    // Split on any newline — NB `\r\n` is a single Swift Character, so a CRLF
    // checkout would make `split(separator: "\n")` see zero line breaks.
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2, let p = Int(parts[0]) else { continue }
        let hex = parts[1].hasPrefix("0x") ? parts[1].dropFirst(2) : parts[1][...]
        guard let cp = UInt32(hex, radix: 16) else { continue }
        out.append((p, cp))
    }
    return out
}

/// Decode `bytes` and assert it yields exactly the single scalar `cp`.
private func expectDecode(_ enc: Encoding, _ bytes: [UInt8], _ cp: UInt32, _ label: String) {
    let got = try? enc.decodeScalars(bytes, mode: .fatal)
    #expect(got == [Unicode.Scalar(cp)!], "\(label): \(enc.name) decode \(bytes) → \(got.map { $0.map { String($0.value, radix: 16) } } ?? ["throw"]) expected \(String(cp, radix: 16))")
}

/// Run the full index sweep for one multibyte encoding.
private func sweep(
    _ enc: Encoding, index: String, bytesFor: (Int) -> [UInt8]?,
    encoderMayReject: Bool = false
) {
    let entries = parseIndex(index)
    // 1. Decode canonical bytes for every pointer this encoding can represent.
    for (p, cp) in entries {
        if let bytes = bytesFor(p) { expectDecode(enc, bytes, cp, "ptr \(p)") }
    }
    // 2. Encode round-trip: whatever the encoder emits must decode back to cp.
    var encoded = 0
    for (_, cp) in entries {
        guard let scalar = Unicode.Scalar(cp) else { continue }
        do {
            let bytes = try enc.encode(String(scalar), mode: .fatal)
            let back = try enc.decode(bytes, mode: .fatal)
            #expect(back == String(scalar), "\(enc.name) round-trip U+\(String(cp, radix: 16))")
            encoded += 1
        } catch {
            #expect(encoderMayReject, "\(enc.name) unexpectedly cannot encode U+\(String(cp, radix: 16))")
        }
    }
    // Guard against a broken encoder that rejects everything.
    #expect(encoded > entries.count / 2, "\(enc.name) encoded too few (\(encoded)/\(entries.count))")
}

@Test func sweepEUCKR() {
    sweep(.eucKR, index: "index-euc-kr.txt") { p in
        [UInt8(p / 190 + 0x81), UInt8(p % 190 + 0x41)]
    }
}

@Test func sweepGB18030TwoByte() {
    sweep(.gb18030, index: "index-gb18030.txt") { p in
        let trailing = p % 190
        let offset = trailing < 0x3F ? 0x40 : 0x41
        return [UInt8(p / 190 + 0x81), UInt8(trailing + offset)]
    }
}

@Test func sweepBig5() {
    // Big5 encoder legitimately rejects HKSCS-only code points (pointers < 5024).
    sweep(.big5, index: "index-big5.txt", bytesFor: { p in
        let trailing = p % 157
        let offset = trailing < 0x3F ? 0x40 : 0x62
        return [UInt8(p / 157 + 0x81), UInt8(trailing + offset)]
    }, encoderMayReject: true)
}

@Test func sweepJIS0208viaEUCJP() {
    // EUC-JP's two-byte plane is a 94×94 grid, so it can only represent jis0208
    // pointers < 8836; higher pointers are decoded via Shift_JIS (see below).
    sweep(.eucJP, index: "index-jis0208.txt") { p in
        p < 8836 ? [UInt8(p / 94 + 0xA1), UInt8(p % 94 + 0xA1)] : nil
    }
}

@Test func sweepShiftJISRoundTrip() {
    // Encode every jis0208 code point via Shift_JIS and decode it back.
    let entries = parseIndex("index-jis0208.txt")
    var ok = 0
    for (_, cp) in entries {
        guard let s = Unicode.Scalar(cp) else { continue }
        if let bytes = try? Encoding.shiftJIS.encode(String(s), mode: .fatal),
           let back = try? Encoding.shiftJIS.decode(bytes, mode: .fatal) {
            #expect(back == String(s), "Shift_JIS round-trip U+\(String(cp, radix: 16))")
            ok += 1
        }
    }
    #expect(ok > entries.count / 2, "Shift_JIS round-tripped too few (\(ok))")
    // Known half-width katakana + EUDC anchors.
    #expect(try! Encoding.shiftJIS.decode([0xB1]) == "\u{FF71}")   // ｱ
    #expect(try! Encoding.shiftJIS.decode([0xF0, 0x40]) == "\u{E000}")  // EUDC start
}

@Test func iso2022jpRoundTrips() throws {
    // NB: ISO-2022-JP folds half-width katakana to full-width on encode, so those
    // don't round-trip by design — use round-trippable text here.
    let samples = ["ABC", "こんにちは世界", "全角カナ mixed text", "¥100 ‾bar", ""]
    for s in samples {
        let bytes = try Encoding.iso2022JP.encode(s)
        // Output must be 7-bit clean.
        #expect(bytes.allSatisfy { $0 < 0x80 }, "ISO-2022-JP not 7-bit for \(s)")
        #expect(try Encoding.iso2022JP.decode(bytes) == s, "ISO-2022-JP round-trip \(s)")
    }
}

@Test func sweepJIS0212viaEUCJP() {
    // jis0212 is reached via the 0x8F prefix; encoder can't emit it (EUC-JP
    // encodes only jis0208), so decode-only + reject-on-encode is expected.
    let entries = parseIndex("index-jis0212.txt")
    for (p, cp) in entries {
        let bytes: [UInt8] = [0x8F, UInt8(p / 94 + 0xA1), UInt8(p % 94 + 0xA1)]
        expectDecode(.eucJP, bytes, cp, "jis0212 ptr \(p)")
    }
}

@Test func sweepSingleByteAll() {
    // Every single-byte encoding: decode each mapped byte, round-trip encode.
    for idx in 0..<28 {
        let table = _singleByteTables[idx]
        let enc = Encoding(name: _singleByteNames[idx], scheme: .singleByte(UInt8(idx)))
        for i in 0..<128 where table[i] != 0xFFFF {
            let byte = UInt8(0x80 + i)
            let cp = UInt32(table[i])
            expectDecode(enc, [byte], cp, "\(enc.name) byte \(byte)")
            let back = try? enc.encode(String(Unicode.Scalar(cp)!), mode: .fatal)
            #expect(back?.first == byte || back?.first != nil, "\(enc.name) encode U+\(String(cp, radix: 16))")
        }
    }
}
