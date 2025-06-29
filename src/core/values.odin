package aincore

Number :: struct {
    numeral: i64,
    denominator: i64,
}

Func :: struct {
    name: string,
    params: []FuncParam,
    body: ^Stmt,
    is_builtin: bool,
    scope: ^Scope,
}

FuncParam :: struct {
    name: string,
    is_rest: bool,
}

Nil :: distinct ^u8

Bool :: bool

Scope :: struct {
    vars: map[string]Value,
    parent: ^Scope,
}

Value :: union {
    Number,
    Nil,
    Bool,
    String,
    ^Func,
    ^Array,
    ^Struct,
    Module,
    rawptr,
}

Module :: distinct string

ValueType :: enum {
    Number,
    Func,
    Nil,
    Bool,
    String,
    Array,
    Struct,
    Module,
    rawptr,
}

valueToValueType :: proc(v: Value) -> ValueType {
    switch v in v {
    case Module: return .Module
    case Number: return .Number
    case Nil: return .Nil
    case Bool: return .Bool
    case String: return .String
    case ^Func: return .Func
    case ^Array: return .Array
    case ^Struct: return .Struct
    case rawptr: return .rawptr
    }
    return {}
}

Array :: struct {
    values: [dynamic]Value,
}

String :: string

StructField :: struct {
    name: string,
    value: Value,
}

Struct :: struct {
    fields: []StructField,
    ref_count: int,
}
