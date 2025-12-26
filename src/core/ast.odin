package aincore

File :: struct {
    statements: []^Stmt,
    path: string,
    src: string,
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
    then_branch: ^Stmt,
    else_branch: ^Stmt,
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

IndexExpr :: struct {
    indexable: ^Expr,
    index: ^Expr,
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
    String,
    Number,
    Bool,
    ArrayExpr,
    Nil,
}

ArrayExpr :: struct {
    values: []^Expr,
}

UnaryExpr :: struct {
    expr: ^Expr,
    op: UnaryOp,
}

UnaryOp :: enum {
    Minus,
    Identity,
    Negate,
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
    IndexExpr,
    UnaryExpr,
    StructExpr,
    AccessExpr,
}

StructExpr :: struct {
    fields: []StructFieldExpr,
}

StructFieldExpr :: struct {
    name: string,
    value: ^Expr,
}

AccessExpr :: struct {
    field_name: string,
    expr: ^Expr,
}
