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
}

Nil :: distinct ^u8

Bool :: bool

Scope :: struct {
    vars: map[string]Value,
    ref_count: int,
    parent: ^Scope,
}

Value :: union {
    Number,
    Func,
    Nil,
    Bool,
    String,
}

String :: distinct string
