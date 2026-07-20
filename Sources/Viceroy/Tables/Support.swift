//===----------------------------------------------------------------------===//
// Viceroy — Shared table helpers.
//
// Deliberately tiny and encoding-agnostic. Each encoding family's tables live in
// their own file (JIS0208Tables.swift, Big5Tables.swift, …) so the linker can
// pull in only the families a program actually uses: object-file granularity is
// what makes pay-per-use possible. Nothing encoding-specific belongs here.
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
