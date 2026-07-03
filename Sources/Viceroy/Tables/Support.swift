//===----------------------------------------------------------------------===//
// Viceroy — Table support (hand-written; the generated files hold only data).
//
// Large multibyte indexes ship as base64-packed `StaticString`s (fast to
// compile, small, zero-dependency) and are materialized once, on first use,
// into `ContiguousArray`s. Single-byte reverse (encode) maps are derived once
// from the forward tables — we never ship a second copy of the data.
//===----------------------------------------------------------------------===//

/// Decode a base64 `StaticString` (standard alphabet, `=`/newlines ignored).
func base64Decode(_ s: StaticString) -> [UInt8] {
    var out = [UInt8]()
    s.withUTF8Buffer { buf in
        out.reserveCapacity((buf.count / 4) * 3)
        var acc: UInt32 = 0
        var bits = 0
        for c in buf {
            let v: UInt32
            switch c {
            case 0x41...0x5A: v = UInt32(c) - 0x41          // A–Z → 0…25
            case 0x61...0x7A: v = UInt32(c) - 0x61 + 26     // a–z → 26…51
            case 0x30...0x39: v = UInt32(c) - 0x30 + 52     // 0–9 → 52…61
            case 0x2B: v = 62                                // +
            case 0x2F: v = 63                                // /
            default: continue                                // '=' or stray byte
            }
            acc = (acc << 6) | v
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((acc >> UInt32(bits)) & 0xFF))
            }
        }
    }
    return out
}

/// Materialize a big-endian `UInt16` table.
func decodeU16Table(_ s: StaticString, count: Int) -> [UInt16] {
    let bytes = base64Decode(s)
    var t = [UInt16](repeating: 0, count: count)
    for i in 0..<count {
        t[i] = (UInt16(bytes[2 * i]) << 8) | UInt16(bytes[2 * i + 1])
    }
    return t
}

/// Materialize a big-endian `UInt32` table.
func decodeU32Table(_ s: StaticString, count: Int) -> [UInt32] {
    let bytes = base64Decode(s)
    var t = [UInt32](repeating: 0, count: count)
    for i in 0..<count {
        let b = 4 * i
        t[i] = (UInt32(bytes[b]) << 24) | (UInt32(bytes[b + 1]) << 16)
             | (UInt32(bytes[b + 2]) << 8) | UInt32(bytes[b + 3])
    }
    return t
}

// Forward decode tables (pointer → code point; 0xFFFF / 0xFFFFFFFF = unmapped).
let jis0208: [UInt16]   = decodeU16Table(_jis0208_b64, count: _jis0208_count)
let jis0212: [UInt16]   = decodeU16Table(_jis0212_b64, count: _jis0212_count)
let eucKRIndex: [UInt16] = decodeU16Table(_eucKR_b64, count: _eucKR_count)
let gb18030Index: [UInt16] = decodeU16Table(_gb18030_b64, count: _gb18030_count)
let big5Index: [UInt32] = decodeU32Table(_big5_b64, count: _big5_count)

// Single-byte reverse (encode) maps: code point → byte (0x80…0xFF). Lowest byte
// wins on the rare duplicate, matching WHATWG "index pointer for code point".
let _singleByteReverse: [[UInt32: UInt8]] = _singleByteTables.map { table in
    var m = [UInt32: UInt8](minimumCapacity: 128)
    for i in 0..<128 {
        let cp = table[i]
        if cp != 0xFFFF {
            let key = UInt32(cp)
            if m[key] == nil { m[key] = UInt8(0x80 + i) }
        }
    }
    return m
}

// MARK: - Multibyte reverse (encode) maps

/// "index pointer for code point": the first (lowest) pointer mapping to `cp`,
/// optionally excluding a pointer range (Shift_JIS skips 8272…8835).
func buildFirstPointerMap(_ table: [UInt16], skip: ClosedRange<Int>? = nil) -> [UInt32: Int] {
    var m = [UInt32: Int](minimumCapacity: table.count)
    for p in 0..<table.count {
        if let s = skip, s.contains(p) { continue }
        let cp = table[p]
        if cp == 0xFFFF { continue }
        let key = UInt32(cp)
        if m[key] == nil { m[key] = p }
    }
    return m
}

let jis0208Reverse  = buildFirstPointerMap(jis0208)                 // EUC-JP, ISO-2022-JP
let shiftJISReverse = buildFirstPointerMap(jis0208, skip: 8272...8835)
let eucKRReverse    = buildFirstPointerMap(eucKRIndex)
let gb18030Reverse  = buildFirstPointerMap(gb18030Index)

/// Big5 encode map: index restricted to pointers ≥ (0xA1−0x81)×157 = 5024
/// (avoids emitting HKSCS extensions), first pointer wins — except six code
/// points that use the *last* pointer, per WHATWG "index Big5 pointer".
let big5Reverse: [UInt32: Int] = {
    let lowerBound = (0xA1 - 0x81) * 157   // 5024
    var m = [UInt32: Int](minimumCapacity: big5Index.count)
    for p in lowerBound..<big5Index.count {
        let cp = big5Index[p]
        if cp == 0xFFFF_FFFF { continue }
        if m[cp] == nil { m[cp] = p }
    }
    for cp in [0x2550, 0x255E, 0x2561, 0x256A, 0x5341, 0x5345] as [UInt32] {
        var last: Int? = nil
        for p in lowerBound..<big5Index.count where big5Index[p] == cp { last = p }
        if let last { m[cp] = last }
    }
    return m
}()

// MARK: - gb18030 four-byte ranges (algorithmic; ranges are ascending in both columns)

/// WHATWG "index gb18030 ranges code point for pointer" (4-byte decode).
func gb18030RangesCodePoint(_ pointer: UInt32) -> UInt32? {
    if (pointer > 39419 && pointer < 189000) || pointer > 1237575 { return nil }
    if pointer == 7457 { return 0xE7C7 }
    var lo = 0, hi = _gb18030RangesPointers.count - 1, idx = 0
    while lo <= hi {
        let mid = (lo + hi) / 2
        if _gb18030RangesPointers[mid] <= pointer { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
    }
    return _gb18030RangesCodePoints[idx] + (pointer - _gb18030RangesPointers[idx])
}

/// WHATWG "index gb18030 ranges pointer for code point" (4-byte encode).
func gb18030RangesPointer(_ cp: UInt32) -> UInt32 {
    if cp == 0xE7C7 { return 7457 }
    var lo = 0, hi = _gb18030RangesCodePoints.count - 1, idx = 0
    while lo <= hi {
        let mid = (lo + hi) / 2
        if _gb18030RangesCodePoints[mid] <= cp { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
    }
    return _gb18030RangesPointers[idx] + (cp - _gb18030RangesCodePoints[idx])
}

/// The gb18030 encoder's asymmetric PUA side-table (WHATWG §10.2.2). These 18
/// private-use code points encode to fixed two-byte sequences, preserving
/// GB18030-2005 compatibility; the index maps them elsewhere on decode.
let gb18030EncoderSideTable: [UInt32: (UInt8, UInt8)] = [
    0xE78D: (0xA6, 0xD9), 0xE78E: (0xA6, 0xDA), 0xE78F: (0xA6, 0xDB),
    0xE790: (0xA6, 0xDC), 0xE791: (0xA6, 0xDD), 0xE792: (0xA6, 0xDE),
    0xE793: (0xA6, 0xDF), 0xE794: (0xA6, 0xEC), 0xE795: (0xA6, 0xED),
    0xE796: (0xA6, 0xF3), 0xE81E: (0xFE, 0x59), 0xE826: (0xFE, 0x61),
    0xE82B: (0xFE, 0x66), 0xE82C: (0xFE, 0x67), 0xE832: (0xFE, 0x6D),
    0xE843: (0xFE, 0x7E), 0xE854: (0xFE, 0x90), 0xE864: (0xFE, 0xA0),
]
