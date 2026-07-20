#if Korean
// EUC-KR (Wansung + UHC / cp949) tables.
let eucKRIndex: [UInt16] = decodeU16Table(_eucKR_b64, count: _eucKR_count)
let eucKRReverse = buildFirstPointerMap(eucKRIndex)
#endif
