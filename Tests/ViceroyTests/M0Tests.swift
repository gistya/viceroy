import Testing
@testable import Viceroy

// MARK: - Label lookup

@Test func labelResolvesCanonicalNames() {
    #expect(Encoding(label: "utf-8")?.name == "UTF-8")
    #expect(Encoding(label: "  UTF-8 ")?.name == "UTF-8")          // whitespace + case
    #expect(Encoding(label: "latin1")?.name == "windows-1252")     // WHATWG quirk
    #expect(Encoding(label: "iso-8859-1")?.name == "windows-1252")
    #expect(Encoding(label: "ascii")?.name == "windows-1252")
    #expect(Encoding(label: "utf-16")?.name == "UTF-16LE")
    #expect(Encoding(label: "shift-jis")?.name == "Shift_JIS")
    #expect(Encoding(label: "csiso2022kr")?.name == "replacement")
    #expect(Encoding(label: "totally-bogus") == nil)
}

// MARK: - UTF-8

@Test func utf8RoundTrips() throws {
    let s = "Hello, 世界! — café ☕️ 𝄞"
    let bytes = try Encoding.utf8.encode(s)
    #expect(try Encoding.utf8.decode(bytes) == s)
}

@Test func utf8StripsBOM() throws {
    let bytes: [UInt8] = [0xEF, 0xBB, 0xBF, 0x41, 0x42]
    #expect(try Encoding.utf8.decode(bytes) == "AB")
}

@Test func utf8ReplacesInvalid() throws {
    // 0x80 is a lone continuation → one U+FFFD; then "A".
    #expect(try Encoding.utf8.decode([0x80, 0x41]) == "\u{FFFD}A")
    // Truncated 3-byte sequence at EOF → one U+FFFD.
    #expect(try Encoding.utf8.decode([0xE2, 0x82]) == "\u{FFFD}")
    // Overlong / invalid lead.
    #expect(try Encoding.utf8.decode([0xC0, 0x80]) == "\u{FFFD}\u{FFFD}")
}

@Test func utf8FatalThrows() {
    #expect(throws: ViceroyError.self) {
        _ = try Encoding.utf8.decode([0x41, 0xFF], mode: .fatal)
    }
}

// MARK: - UTF-16

@Test func utf16RoundTrips() throws {
    let s = "AZ 世界 𝄞 café"
    for enc in [Encoding.utf16le, .utf16be] {
        let bytes = try enc.encode(s)
        #expect(try enc.decode(bytes) == s, "\(enc.name)")
    }
}

@Test func utf16LEDecodesKnownBytes() throws {
    // "AB𝄞" in UTF-16LE: 41 00, 42 00, then surrogate pair D834 DD1E → 34 D8 1E DD
    let bytes: [UInt8] = [0x41, 0x00, 0x42, 0x00, 0x34, 0xD8, 0x1E, 0xDD]
    #expect(try Encoding.utf16le.decode(bytes) == "AB𝄞")
}

@Test func utf16StripsBOM() throws {
    #expect(try Encoding.utf16le.decode([0xFF, 0xFE, 0x41, 0x00]) == "A")
    #expect(try Encoding.utf16be.decode([0xFE, 0xFF, 0x00, 0x41]) == "A")
}

@Test func utf16LoneSurrogateReplaced() throws {
    // Lone high surrogate D800 (LE: 00 D8) then "A" (41 00).
    #expect(try Encoding.utf16le.decode([0x00, 0xD8, 0x41, 0x00]) == "\u{FFFD}A")
}

// MARK: - Single-byte

@Test func windows1252KnownBytes() throws {
    // 0x80 → EURO SIGN, 0xA9 → ©, 0x41 → A
    #expect(try Encoding.windows1252.decode([0x80, 0xA9, 0x41]) == "€©A")
}

@Test func windows1252Encodes() throws {
    #expect(try Encoding.windows1252.encode("€©A") == [0x80, 0xA9, 0x41])
}

@Test func iso88592RoundTrips() throws {
    // Every mappable byte 0x00…0xFF should survive decode→encode.
    let enc = Encoding.iso8859_2
    var bytes: [UInt8] = []
    for b in UInt8(0)...UInt8(255) where b != 0xA1 || true { bytes.append(b) }
    let s = try enc.decode(bytes, mode: .replacement)
    // Re-encode only the scalars that were mappable (no U+FFFD present here since
    // ISO-8859-2 maps all 256 bytes).
    #expect(!s.unicodeScalars.contains("\u{FFFD}"))
    let re = try enc.encode(s)
    #expect(re == bytes)
}

@Test func singleByteUnmappableByteReplaced() throws {
    // windows-1257 has holes; 0xA1 is unmapped → U+FFFD.
    let s = try Encoding.windows1257.decode([0xA1])
    #expect(s == "\u{FFFD}")
}

@Test func encodeUnmappableFatalThrows() {
    #expect(throws: ViceroyError.self) {
        _ = try Encoding.windows1252.encode("世", mode: .fatal)
    }
}

@Test func encodeUnmappableReplacement() throws {
    #expect(try Encoding.windows1252.encode("A世B", mode: .questionMark) == [0x41, 0x3F, 0x42])
}

@Test func encodeUnmappableHTMLEscape() throws {
    // 世 = U+4E16 = 19990
    let out = try Encoding.windows1252.encode("世", mode: .htmlNumericEscape)
    #expect(out == Array("&#19990;".utf8))
}

// MARK: - x-user-defined

@Test func xUserDefinedRoundTrips() throws {
    let bytes: [UInt8] = [0x41, 0x80, 0xFF, 0x7F]
    let s = try Encoding.xUserDefined.decode(bytes)
    #expect(Array(s.unicodeScalars.map(\.value)) == [0x41, 0xF780, 0xF7FF, 0x7F])
    #expect(try Encoding.xUserDefined.encode(s) == bytes)
}

// MARK: - replacement

@Test func replacementDecoderEmitsSingleFFFD() throws {
    #expect(try Encoding.replacement.decode([0x41, 0x42, 0x43]) == "\u{FFFD}")
    #expect(try Encoding.replacement.decode([]) == "")
}
