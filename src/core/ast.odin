package aincore

File :: struct {
    statements: []^Stmt,
}

Stmt :: struct {
    loc: Location,
    vart: StmtVart,
}

StmtVart :: union {
    StmtExpr,
}

StmtExpr :: struct {
    expr: ^Expr,
}

LiteralExpr :: union {
    Number,
}

BinaryExpr :: struct {
    left: ^Expr,
    op: BinOp,
    right: ^Expr,
}

BinOp :: enum {
    Plus,
    Minus,
    Multiply,
    Divide,
}

Expr :: struct {
    loc: Location,
    vart: ExprVart,
}

ExprVart :: union {
    LiteralExpr,
    BinaryExpr,
}

