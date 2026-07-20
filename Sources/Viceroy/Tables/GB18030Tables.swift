#if Chinese
// gb18030 / GBK tables + the algorithmic four-byte range machinery.

let gb18030Index: [UInt16] = decodeU16Table(_gb18030_b64, count: _gb18030_count)
let gb18030Reverse = buildFirstPointerMap(gb18030Index)

// Ranges are ascending in both columns, so both lookups binary-search.

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
#endif
