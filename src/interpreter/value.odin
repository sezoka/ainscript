package aininterpreter

import "../core"
import "core:fmt"
import "core:strings"

makeValue_Pointer :: proc(ptr: rawptr) -> core.Value {
    return ptr
}

makeValue_Array :: proc(values: [dynamic]core.Value) -> core.Value {
    arr := new(core.Array)
    for &v in values {
        increaseValueRefCount(v)
    }
    arr.values = values
    return arr
}

makeValue_Struct :: proc(fields: []core.StructField) -> core.Value {
    strct := new(core.Struct)
    strct.fields = fields
    return strct
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

increaseValueRefCount :: proc(val: core.Value) {
    switch &v in val {
    case core.Number, core.Nil, core.Bool, core.String, rawptr:
        return
    case ^core.Array:
        v.ref_count += 1
    case ^core.Struct:
        v.ref_count += 1
    case core.Func:
    }
}

deleteValue :: proc(val: core.Value) {
    switch &v in val {
    case core.Number, core.Nil, core.Bool, core.String, rawptr:
        return
    case ^core.Array:
        assert(v.ref_count != 0)
        v.ref_count -= 1
        if v.ref_count <= 0 {
            for item in v.values {
                deleteValue(item)
            }
            delete(v.values)
            free(v)
        }
    case ^core.Struct:
        assert(v.ref_count != 0)
        v.ref_count -= 1
        if v.ref_count <= 0 {
            for field in v.fields {
                deleteValue(field.value)
            }
            delete(v.fields)
            free(v)
        }
    case core.Func:
    }
}

formatValue :: proc(val: core.Value) -> string {
    b: strings.Builder
    strings.builder_init(&b, allocator=context.temp_allocator)
    formatValueImpl(&b, val)
    return strings.to_string(b)
}

formatType :: proc(val: core.Value) -> string {
    formatTypeImpl :: proc(b: ^strings.Builder, val: core.Value) {
        switch v in val {
        case core.Number:
            strings.write_string(b, "number")
        case core.Func:
            strings.write_string(b, formatValue(val))
        case core.Nil:
            strings.write_string(b, "nil")
        case core.Bool:
            strings.write_string(b, "bool")
        case core.String:
            strings.write_string(b, "string")
        case ^core.Array:
            strings.write_string(b, "array")
        case ^core.Struct:
            strings.write_string(b, "#{ ")
            for field, i in v.fields {
                strings.write_string(b, field.name)
                if i != len(v.fields) - 1 {
                    strings.write_string(b, ",")
                }
                strings.write_string(b, " ")
            }
            strings.write_string(b, "}")

        case rawptr:
        }
    }

    b: strings.Builder
    strings.builder_init(&b, allocator=context.temp_allocator)
    formatTypeImpl(&b, val)
    return strings.to_string(b)
}

formatValueImpl :: proc(b: ^strings.Builder, val: core.Value) {
    switch v in val {
    case rawptr:
        strings.write_string(b, "ptr(")
        strings.write_int(b, int(uintptr(v)))
        strings.write_string(b, ")")
    case ^core.Struct:
        strings.write_string(b, "#{ ")
        for field, i in v.fields {
            strings.write_string(b, field.name)
            strings.write_string(b, "=")
            formatValueImpl(b, field.value)
            if i != len(v.fields) - 1 {
                strings.write_string(b, ",")
            }
            strings.write_string(b, " ")
        }
        strings.write_string(b, " }")
    case ^core.Array:
        strings.write_string(b, "{ ")
        for value, i in v.values {
            formatValueImpl(b, value)
            if i != len(v.values) - 1 {
                strings.write_string(b, ", ")
            }
            strings.write_string(b, " ")
        }
        strings.write_string(b, "}")
    case core.String:
        strings.write_string(b, v)
    case core.Number:
        num := normalizeNumber(v)
        float := f64(num.numeral) / f64(num.denominator)
        strings.write_f64(b, float, 'f')
    case core.Func:
        strings.write_string(b, "def ")
        strings.write_string(b, v.name)
        strings.write_string(b, "(")
        for param, i in v.params {
            strings.write_string(b, param.name)
            if i != len(v.params) - 1 {
                strings.write_string(b, " ")
            }
        }
        strings.write_string(b, ")")
    case core.Nil:
        strings.write_string(b, "nil")
    case core.Bool:
        strings.write_string(b, v ? "true" : "false")
    }
}

printValue :: proc(val: core.Value) {
    fmt.print(formatValue(val))
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
