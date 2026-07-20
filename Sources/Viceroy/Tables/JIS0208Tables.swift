#if Japanese
// JIS X 0208 tables — shared by Shift_JIS, EUC-JP and ISO-2022-JP.
let jis0208: [UInt16] = decodeU16Table(_jis0208_b64, count: _jis0208_count)
let jis0208Reverse  = buildFirstPointerMap(jis0208)                  // EUC-JP, ISO-2022-JP
let shiftJISReverse = buildFirstPointerMap(jis0208, skip: 8272...8835)
#endif
