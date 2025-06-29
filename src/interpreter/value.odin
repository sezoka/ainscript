package aininterpreter

import "../core"
import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strings"

makeValue_Pointer :: proc(ptr: rawptr) -> core.Value {
    return ptr
}

makeValue_Module :: proc(path: string) -> core.Value {
    return core.Module(path)
}

makeValue_Array :: proc(intr: ^Interpreter, values: [dynamic]core.Value) -> core.Value {
    arr := new(core.Array)
    arr.values = values
    intr.heap_allocated_values[arr] = arr
    return arr
}

unionsEql :: proc(a: any, b: any) -> bool {
    return reflect.union_variant_typeid(a) == reflect.union_variant_typeid(b)
}

valuesEql :: proc(a: core.Value, b: core.Value) -> bool {
    if unionsEql(a, b) {
        switch v in a {
        case core.Module:
            return v == b.(core.Module)
        case core.Number:
            a := v
            b := b.(core.Number)
            return a.numeral * b.denominator == b.numeral * a.denominator
        case core.Nil:
            return true
        case core.Bool:
            return v == b.(core.Bool)
        case core.String:
            return v == b.(core.String)
        case ^core.Array:
            return v == b.(^core.Array)
        case ^core.Struct:
            return v == b.(^core.Struct)
        case ^core.Func:
            return v == b.(^core.Func)
        case rawptr:
            return v == b.(rawptr)
        }
    }
    return false
}

makeValue_Struct :: proc(intr: ^Interpreter, fields: []core.StructField) -> core.Value {
    strct := new(core.Struct)
    strct.fields = fields
    intr.heap_allocated_values[strct] = strct
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

makeValue_Func :: proc(
    intr: ^Interpreter,
    name: string,
    params: []core.FuncParam,
    body: ^core.Stmt,
    scope: ^core.Scope,
    is_builtin := false,
) -> core.Value {
    func := new(core.Func)
    func.name = name
    func.params = params
    func.body = body
    func.is_builtin = is_builtin
    func.scope = scope

    intr.functions[func] = {}

    return func
}

deleteValue :: proc(intr: ^Interpreter, val: core.Value) {
    switch &v in val {
    case core.Number, core.Nil, core.Bool, core.String, core.Module, rawptr:
        return
    case ^core.Array:
        delete(v.values)
        delete_key(&intr.heap_allocated_values, v)
        free(v)
    case ^core.Struct:
        delete(v.fields)
        delete_key(&intr.heap_allocated_values, v)
        free(v)
    case ^core.Func:
        delete_key(&intr.functions, v)
        free(v)
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
        case ^core.Func:
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
        case core.Module:
            strings.write_string(b, "module(")
            strings.write_string(b, string(v))
            strings.write_string(b, ")")
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
        strings.write_string(b, "}")
    case ^core.Array:
        strings.write_string(b, "{ ")
        for value, i in v.values {
            formatValueImpl(b, value)
            if i != len(v.values) - 1 {
                strings.write_string(b, ",")
            }
            strings.write_string(b, " ")
        }
        strings.write_string(b, "}")
    case core.String:
        strings.write_string(b, v)
    case core.Number:
        num := normalizeNumber(v)
        float := f64(num.numeral) / f64(num.denominator)
        if num.denominator == 1 {
            strings.write_i64(b, num.numeral)
        } else {
            strings.write_f64(b, float, 'f')
        }
    case ^core.Func:
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
    case core.Module:
        strings.write_string(b, "module(")
        strings.write_string(b, string(v))
        strings.write_string(b, ")")
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
