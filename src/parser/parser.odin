package ainparser

import "../core"
import "core:fmt"
import "core:log"
import "../tokenizer/"
import "core:strings"

Parser :: struct {
    had_error: bool,
    tokens: []tokenizer.Token,
    curr: int,
}

parseFile :: proc(tokens: []tokenizer.Token) -> (file: core.File, ok: bool) {
    parser : Parser
    parser.tokens = tokens

    stmts := make([dynamic]^core.Stmt)

    for peek(&parser).kind != .Eof {
        stmt, stmt_ok := parseStmt(&parser)
        if !stmt_ok do return {}, false
        append(&stmts, stmt)
    }

    shrink(&stmts)
    file.statements = stmts[:]
    return file, true
}

expectSemicolon :: proc(p: ^Parser) -> bool {
    tok := peek(p)
    if matches(p, .Semicolon) {
        return true
    } else {
        reportError(p, tok.loc, "expect ';'")
        return false
    }
}



parseStmt :: proc(p: ^Parser) -> (stmt: ^core.Stmt, ok: bool) {
    if matches(p, .LeftBrace) {
        stmts : [dynamic]^core.Stmt
        for !matches(p, .RightBrace) {
            append(&stmts, parseStmt(p) or_return)
        }
    } else if matches(p, .Var) {
        ident_expr := parseExpr(p) or_return
        ident, is_ident := ident_expr.vart.(core.IdentExpr)
        if is_ident {
            if matches(p, .Equal) {
                val := parseExpr(p) or_return
                expectSemicolon(p) or_return
                return makeStmt(ident_expr.loc, core.VarStmt{name = ident.name, value = val})
            } else {
                reportError(p, ident_expr.loc, "expect '=' after variable name")
                return {}, false
            }
        } else {
            reportError(p, ident_expr.loc, "expect variable name, but got '%v'", ident_expr.vart)
            return {}, false
        }
    }

    expr := parseExpr(p) or_return

    if matches(p, .Equal) {
        ident, is_ident := expr.vart.(core.IdentExpr)
        if is_ident {
            val := parseExpr(p) or_return
            expectSemicolon(p) or_return
            return makeStmt(expr.loc, core.AssignStmt{name = ident.name, value = val})
        } else {
            reportError(p, expr.loc, "expect variable name, but got '%v'", expr.vart)
            return {}, false
        }
    } if matches(p, .Semicolon) {
        return makeStmt(expr.loc, core.ExprStmt{ expr = expr })
    }

    reportError(p, expr.loc, "unexpected token '%v'", peek(p).kind)

    return {}, false
}

parseExpr :: proc(p: ^Parser) -> (^core.Expr, bool) {
    return parseBinary(p)
}

parseBinary :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    left := parsePrimary(p) or_return

    bin_op_tokens := [?]tokenizer.TokenKind{ .Plus, .Minus, .Star, .Slash }
    for tok, matches := matchesAny(p, bin_op_tokens[:]);
            matches;
            tok, matches = matchesAny(p, bin_op_tokens[:]) {
        right := parsePrimary(p) or_return

        op : core.BinOp
        #partial switch tok {
        case .Plus:
            op = .Plus
        case .Minus:
            op = .Minus
        case .Star:
            op = .Multiply
        case .Slash:
            op = .Divide
        case: panic("unreachable")
        }

        left = makeExpr(left.loc, core.BinaryExpr{left = left, op = op, right = right}) or_return
    }

    return left, true
} 

matches :: proc(p: ^Parser, t: tokenizer.TokenKind) -> bool {
    tok := peek(p)
    if tok.kind == t {
        next(p)
        return true
    }
    return false
}

expect :: proc(p: ^Parser, t: tokenizer.TokenKind, msg: string, args: ..any) -> bool {
    if matches(p, t) {
        return true
    } else {
        reportError(p, peek(p).loc, msg, ..args)
        return false
    }
}

matchesAny :: proc(p: ^Parser, toks: []tokenizer.TokenKind) -> (tokenizer.TokenKind, bool) {
    tok := peek(p)
    for t in toks {
        if tok.kind == t {
            next(p)
            return tok.kind, true
        }
    }
    return {}, false
}

parsePrimary :: proc(p: ^Parser) -> (^core.Expr, bool) {
    tok := next(p)
    #partial switch tok.kind {
    case .Number:
        return makeExpr(tok.loc, core.LiteralExpr(tok.value.(core.Number)))
    case .Ident:
        return makeExpr(tok.loc, core.IdentExpr{name = tok.value.(string)})
    case:
        reportError(p, tok.loc, "unexpected token '%v'", tok.lexeme)
        return {}, false
    }
    return {}, false
}

makeStmt :: proc(loc: core.Location, v: core.StmtVart) -> (^core.Stmt, bool) {
    stmt := new(core.Stmt)
    stmt.vart = v
    stmt.loc = loc
    return stmt, stmt != nil
}

makeExpr :: proc(loc: core.Location, v: core.ExprVart) -> (^core.Expr, bool) {
    expr := new(core.Expr)
    expr.vart = v
    expr.loc = loc
    return expr, expr != nil
}

next :: proc(t: ^Parser) -> tokenizer.Token {
    curr := t.tokens[t.curr]
    if curr.kind != .Eof {
        t.curr += 1
    }
    return curr
}

peek :: proc(t: ^Parser) -> tokenizer.Token {
    return t.tokens[t.curr]
}

peekNext :: proc(t: ^Parser) -> tokenizer.Token {
    if t.curr + 1 < len(t.tokens) {
        return t.tokens[t.curr + 1]
    } else {
        return t.tokens[t.curr]
    }
}

reportError :: proc(p: ^Parser, loc: core.Location, fmt: string, args: ..any) {
    p.had_error = true
    strs : [2]string = { "Parser: ", fmt }
    str := strings.concatenate(strs[:], allocator=context.temp_allocator)
    core.printErr(loc, str, ..args)
}
