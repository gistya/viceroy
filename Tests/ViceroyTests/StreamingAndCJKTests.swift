import Testing
@testable import Viceroy

// MARK: - Streaming ≡ whole-buffer

private func assertStreamingMatches(_ enc: Encoding, _ bytes: [UInt8], _ label: String) throws {
    let whole = try enc.decode(bytes, mode: .replacement)
    // Split at every possible boundary.
    for split in 0...bytes.count {
        var dec = StreamingDecoder(enc, mode: .replacement)
        var view = String.UnicodeScalarView()
        try dec.decode(bytes[0..<split], into: &view)
        try dec.decode(bytes[split...], into: &view)
        try dec.finish(into: &view)
        #expect(String(view) == whole, "\(label): split at \(split)")
    }
    // Byte-by-byte (worst case for split multibyte / escapes).
    var dec = StreamingDecoder(enc, mode: .replacement)
    var view = String.UnicodeScalarView()
    for b in bytes { try dec.decode(CollectionOfOne(b), into: &view) }
    try dec.finish(into: &view)
    #expect(String(view) == whole, "\(label): byte-by-byte")
}

@Test func streamingEquivalence() throws {
    let text = "Aあ漢字😀 café €"
    for enc in [Encoding.utf8, .utf16le, .utf16be, .shiftJIS, .eucJP, .iso2022JP, .big5, .gb18030, .eucKR] {
        // Encode what each can (replacement for unmappables), then re-decode split.
        let bytes = try enc.encode(text, mode: .questionMark)
        try assertStreamingMatches(enc, bytes, enc.name)
    }
    // With a UTF-8 BOM split across the boundary.
    try assertStreamingMatches(.utf8, [0xEF, 0xBB, 0xBF] + Array("héllo".utf8), "utf8+BOM")
    // Truncated/garbled inputs must still agree.
    try assertStreamingMatches(.shiftJIS, [0x82, 0x41, 0x81], "shiftjis-garbled")
    try assertStreamingMatches(.gb18030, [0x81, 0x30, 0x81, 0x30, 0xFF], "gb18030-4byte+garbage")
}

// MARK: - gb18030 four-byte + GBK divergence

@Test func gb18030FourByte() throws {
    let s = "😀"  // U+1F600, only reachable via the 4-byte algorithm
    let bytes = try Encoding.gb18030.encode(s)
    #expect(bytes.count == 4)
    #expect(try Encoding.gb18030.decode(bytes) == s)
    // GBK cannot represent it.
    #expect(throws: ViceroyError.self) { _ = try Encoding.gbk.encode(s, mode: .fatal) }
}

@Test func gbkEuroDivergesFromGb18030() throws {
    #expect(try Encoding.gbk.encode("€") == [0x80])          // GBK special-case
    #expect(try Encoding.gb18030.encode("€") == [0xA2, 0xE3]) // gb18030 via index
    // Both decode back to the euro sign.
    #expect(try Encoding.gb18030.decode([0x80]) == "€")
    #expect(try Encoding.gb18030.decode([0xA2, 0xE3]) == "€")
}

// MARK: - Big5 two-scalar outputs

@Test func big5TwoScalarPointers() throws {
    // Pointer 1133 → «U+00CA U+0304». Bytes: lead 0x88, trail 0x62.
    let scalars = try Encoding.big5.decodeScalars([0x88, 0x62])
    #expect(scalars.map(\.value) == [0x00CA, 0x0304])
}

// MARK: - Transcoder (A → B)

@Test func transcodeRoundTrips() throws {
    let text = "Aあ漢字 café"
    // For each source encoding, encode → transcode to UTF-8 → compare.
    for src in [Encoding.shiftJIS, .eucJP, .big5, .gb18030] {
        let srcBytes = try src.encode(text, mode: .questionMark)
        let expected = try src.decode(srcBytes)              // what src actually represents
        let t = Transcoder(from: src, to: .utf8)
        let utf8Bytes = try t.transcode(srcBytes)
        #expect(try Encoding.utf8.decode(utf8Bytes) == expected, "\(src.name)→utf8")
    }
    // windows-1252 → UTF-8 for a Latin sample.
    let w = try Encoding.windows1252.encode("café €")
    let t = Transcoder(from: .windows1252, to: .utf8)
    #expect(try Encoding.utf8.decode(try t.transcode(w)) == "café €")
}

// MARK: - Streaming encoder flushes ISO-2022-JP state

@Test func streamingEncoderFlushesEscape() throws {
    var enc = StreamingEncoder(.iso2022JP)
    var out: [UInt8] = []
    try enc.encode("あ".unicodeScalars, into: &out)   // switches to jis0208, stays there
    #expect(out.suffix(3) != [0x1B, 0x28, 0x42])       // not yet flushed
    enc.finish(into: &out)                            // must return to ASCII at EOF
    #expect(out.suffix(3) == [0x1B, 0x28, 0x42])       // trailing ESC ( B
    #expect(try Encoding.iso2022JP.decode(out) == "あ")
    // And chunked-encode ≡ whole-encode.
    #expect(out == (try Encoding.iso2022JP.encode("あ")))
}
