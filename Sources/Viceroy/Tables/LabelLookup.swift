//===----------------------------------------------------------------------===//
// Viceroy — Label lookup. Isolated in its own file so that programs which never
// call `Encoding(label:)` do not link the label table at all.
//===----------------------------------------------------------------------===//

/// Binary-search the ASCII label table for `needle`, returning the encoding index.
///
/// Compares raw bytes rather than `String`s: Swift string equality/hashing is
/// canonical-equivalence based and would link the Unicode normalization tables
/// (`libswiftUnicodeDataTables`) into every binary. WHATWG labels are pure ASCII.
func lookupLabel(_ needle: ArraySlice<UInt8>) -> Int? {
    _labelBlob.withUTF8Buffer { blob -> Int? in
        var lo = 0
        var hi = _labelEncoding.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let start = Int(_labelOffsets[mid])
            let end = Int(_labelOffsets[mid + 1])
            var order = 0
            var i = start
            var j = needle.startIndex
            while i < end && j < needle.endIndex {
                let a = blob[i], b = needle[j]
                if a != b { order = a < b ? -1 : 1; break }
                i += 1; j += 1
            }
            if order == 0 {
                let lenA = end - start, lenB = needle.count
                if lenA != lenB { order = lenA < lenB ? -1 : 1 }
            }
            if order == 0 { return Int(_labelEncoding[mid]) }
            if order < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }
}
