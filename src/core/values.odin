package aincore

Number :: struct {
    numeral: i32,
    denominator: i32,
}

Func :: struct {
    name: string,
    params: []FuncParam,
    body: ^Stmt,
    is_builtin: bool,
}

FuncParam :: struct {
    name: string,
}

Nil :: distinct ^u8

Bool :: bool
