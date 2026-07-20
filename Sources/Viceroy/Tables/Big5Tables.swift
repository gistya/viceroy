#if Chinese
// Big5 tables.
let big5Index: [UInt32] = decodeU32Table(_big5_b64, count: _big5_count)

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
#endif
