package aininterpreter

import "../core"
import "core:fmt"

makeValue_Pointer :: proc(ptr: rawptr) -> core.Value {
    return ptr
}

makeValue_Array :: proc(values: [dynamic]core.Value) -> core.Value {
    return core.Array{values=values}
}

makeValue_Struct :: proc(fields: []core.StructField) -> core.Value {
    return core.Struct{fields=fields}
}

makeValue_Number :: proc(n: core.Number) -> core.Value {
    return n
}

makeValue_Bool :: proc(v: bool) -> core.Value {
    return v
}

makeValue_Nil :: proc() -> core.Value {
    return core.Nil(nil)
}

makeValue_Func :: proc(name: string,
    params: []core.FuncParam,
    body: ^core.Stmt,
    scope: ^core.Scope,
    is_builtin := false,
) -> core.Value {
    return core.Func{ 
        name = name,
        params = params,
        body = body,
        is_builtin = is_builtin,
        scope = scope
    }
}

printValue :: proc(val: core.Value) {
    switch v in val {
    case rawptr:
        fmt.printf("ptr(%d)", v)
    case core.Struct:
        fmt.print("#{ ")
        for field, i in v.fields {
            fmt.print(field.name)
            fmt.print("=")
            printValue(field.value)
            if i != len(v.fields) - 1 {
                fmt.print(",")
            }
            fmt.print(" ")
        }
        fmt.print("}")
    case core.Array:
        fmt.print("{ ")
        for value, i in v.values {
            printValue(value)
            if i != len(v.values) - 1 {
                fmt.print(",")
            }
            fmt.print(" ")
        }
        fmt.print("}")
    case core.String:
        fmt.print(v)
    case core.Number:
        num := normalizeNumber(v)
        float := f64(num.numeral) / f64(num.denominator)
        fmt.print(float)
    case core.Func:
        fmt.printf("func(%s)%v", v.name, v.params)
    case core.Nil:
        fmt.print("nil")
    case core.Bool:
        fmt.print(v)
    }
}

normalizeNumber :: proc(v: core.Number) -> core.Number {
    gcd := core.gcd(v.numeral, v.denominator)
    if gcd == 0 {
        return v
    } else {
        numeral := v.numeral / gcd
        denominator := v.denominator / gcd
        return {numeral, denominator}
    }
}
