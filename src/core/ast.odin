package aincore

File :: struct {
    statements: []^Stmt,
}

Stmt :: struct {
    loc: Location,
    vart: StmtVart,
}

StmtVart :: union {
    ExprStmt,
    VarStmt,
    AssignStmt,
    BlockStmt,
    FuncStmt,
}

BlockStmt :: struct {
    stmts: []^Stmt,
}

FuncStmt :: struct {
    name: string,
    params: []string,
    body: []^Stmt,
}

CallExpr :: struct {
    callable: ^Expr,
    params: []^Expr,
}

VarStmt :: struct {
    name: string,
    value: ^Expr,
}

AssignStmt :: struct {
    name: string,
    value: ^Expr,
}

ExprStmt :: struct {
    expr: ^Expr,
}

IdentExpr :: struct {
    name: string,
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
    IdentExpr,
    CallExpr,
}

