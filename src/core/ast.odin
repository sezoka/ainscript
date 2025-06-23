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
    RetStmt,
    WhileStmt,
    IfStmt,
}

IfStmt :: struct {
    cond: ^Expr,
    body: ^Stmt,
}

WhileStmt :: struct {
    cond: ^Expr,
    body: ^Stmt,
}

RetStmt :: struct {
    expr: ^Expr,
}

BlockStmt :: struct {
    stmts: []^Stmt,
}

FuncStmt :: struct {
    name: string,
    params: []FuncParam,
    body: ^Stmt,
    is_builtin: bool,
}

CallExpr :: struct {
    callable: ^Expr,
    args: []^Expr,
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
    Bool,
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
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    Equal,
    NotEqual,
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

