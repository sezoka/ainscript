package aininterpreter

import "../core"
import "core:fmt"

Value :: union {
    core.Number,
}

makeValue_Number :: proc(n: core.Number) -> Value {
    return n
}

printValue :: proc(val: Value) {
    switch v in val {
    case core.Number:
        num := normalizeNumber(v)
        fmt.printfln("%v/%v", num.numeral, num.denominator)
    }
}

normalizeNumber :: proc(v: core.Number) -> core.Number {
    gcd := core.gcd(v.numeral, v.denominator)
    numeral := v.numeral / gcd
    denominator := v.denominator / gcd
    return {numeral, denominator}
}
