package aininterpreter

import "../core"
import "core:fmt"

Value :: union {
    core.Number,
    core.Func,
    core.Nil,
}

makeValue_Number :: proc(n: core.Number) -> Value {
    return n
}

makeValue_Nil :: proc() -> Value {
    return core.Nil(nil)
}

makeValue_Func :: proc(name: string, params: []core.FuncParam, body: []^core.Stmt) -> Value {
    return core.Func{ name, params, body }
}

printValue :: proc(val: Value) {
    switch v in val {
    case core.Number:
        num := normalizeNumber(v)
        fmt.printfln("%v/%v", num.numeral, num.denominator)
    case core.Func:
        fmt.printfln("func(%s)%v", v.name, v.params)
    case core.Nil:
        fmt.println("nil")
    }
}

normalizeNumber :: proc(v: core.Number) -> core.Number {
    gcd := core.gcd(v.numeral, v.denominator)
    numeral := v.numeral / gcd
    denominator := v.denominator / gcd
    return {numeral, denominator}
}
