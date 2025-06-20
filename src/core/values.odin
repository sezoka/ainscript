package aincore

Number :: struct {
    numeral: i32,
    denominator: i32,
}

Func :: struct {
    name: string,
    params: []string,
    body: []^Stmt,
}

Nil :: distinct ^u8
