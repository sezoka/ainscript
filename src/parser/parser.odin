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
    tok := peek(p)
    loc := tok.loc

    if matches(p, .If) {
        cond_expr := parseExpr(p) or_return
        block_loc := peek(p).loc
        expect(p, .Do, "expect 'do' after conditional expression") or_return
        stmts : [dynamic]^core.Stmt
        for !matches(p, .End) {
            stmt := parseStmt(p) or_return
            append(&stmts, stmt)
        }
        return makeStmt(loc, core.IfStmt{body = makeBlockStmt(block_loc, stmts[:]), cond = cond_expr}) 
    } else if matches(p, .While) {
        cond_expr := parseExpr(p) or_return
        block_loc := peek(p).loc
        expect(p, .Do, "expect 'do' after conditional expression") or_return
        stmts : [dynamic]^core.Stmt
        for !matches(p, .End) {
            stmt := parseStmt(p) or_return
            append(&stmts, stmt)
        }
        return makeStmt(loc, core.WhileStmt{body = makeBlockStmt(block_loc, stmts[:]), cond = cond_expr}) 
    } else if matches(p, .Return) {
        if matches(p, .Semicolon) {
            return makeStmt(loc, core.RetStmt{expr = nil})
        } else {
            expr := parseExpr(p) or_return
            expectSemicolon(p)
            return makeStmt(loc, core.RetStmt{expr = expr}) 
        }
    } else if matches(p, .Def) || matches(p, .Builtin) {
        is_builtin := tok.kind == .Builtin
        maybe_ident_tok := next(p)
        if maybe_ident_tok.kind == .Ident {
            name := maybe_ident_tok.value.(string) 

            params : [dynamic]core.FuncParam

            expect(p, .LeftParen, "expect '(' after function name") or_return

            handled_rest_param := false
            rest_param_loc : core.Location
            for peek(p).kind != .RightParen {
                maybe_param_name_tok := next(p)
                if maybe_param_name_tok.kind == .Ident {
                    if handled_rest_param {
                        reportError(p, rest_param_loc, "rest parameter must be latest", )
                        return {}, false
                    }
                    param_name := maybe_param_name_tok.value.(string)
                    append(&params, core.FuncParam{name=param_name})
                } else if maybe_param_name_tok.kind == .DotDot {
                    maybe_param_name_tok := next(p)
                    rest_param_loc = maybe_param_name_tok.loc
                    if maybe_param_name_tok.kind == .Ident {
                        param_name := maybe_param_name_tok.value.(string)
                        handled_rest_param = true
                        append(&params, core.FuncParam{name=param_name, is_rest=true})
                    }
                } else {
                    reportError(p, maybe_param_name_tok.loc, "expect param name, but got '%v'", maybe_param_name_tok.lexeme)
                    return {}, false
                }
            }
            expect(p, .RightParen, "expect ')' after function parameters") or_return

            stmts : [dynamic]^core.Stmt

            body_loc := peek(p).loc

            for !matches(p, .End) {
                append(&stmts, parseStmt(p) or_return)
            }

            return makeStmt(loc, core.FuncStmt{
                name = name,
                body = makeBlockStmt(body_loc, stmts[:]),
                params=params[:],
                is_builtin = is_builtin}
            )
        } else {
            reportError(p, loc, "expect variable name, but got '%v'", maybe_ident_tok.lexeme)
            return {}, false
        }
    } else if matches(p, .Block) {
        stmts : [dynamic]^core.Stmt
        for !matches(p, .End) {
            append(&stmts, parseStmt(p) or_return)
        }
        return makeStmt(loc, core.BlockStmt{stmts = stmts[:]})
    } 

    expr := parseExpr(p) or_return

    if matches(p, .ColonEqual) {
        ident, is_ident := expr.vart.(core.IdentExpr)
        if is_ident {
            val := parseExpr(p) or_return
            expectSemicolon(p) or_return
            return makeStmt(expr.loc, core.VarStmt{name = ident.name, value = val})
        } else {
            reportError(p, expr.loc, "expect variable name, but got '%v'", expr.vart)
            return {}, false
        }
    } else if matches(p, .Equal) {
        ident, is_ident := expr.vart.(core.IdentExpr)
        if is_ident {
            val := parseExpr(p) or_return
            expectSemicolon(p) or_return
            return makeStmt(expr.loc, core.AssignStmt{name = ident.name, value = val})
        } else {
            reportError(p, expr.loc, "expect variable name, but got '%v'", expr.vart)
            return {}, false
        }
    } else if matches(p, .Semicolon) {
        return makeStmt(expr.loc, core.ExprStmt{ expr = expr })
    }

    expectSemicolon(p)

    // reportError(p, expr.loc, "unexpected token '%v'", peek(p).kind)

    return {}, false
}

parseExpr :: proc(p: ^Parser) -> (^core.Expr, bool) {
    return parseEqual(p)
}

parseEqual :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    left := parseLess(p) or_return

    bin_op_tokens := [?]tokenizer.TokenKind{ .EqualEqual, .NotEqual }
    for tok, matches := matchesAny(p, bin_op_tokens[:]);
            matches;
            tok, matches = matchesAny(p, bin_op_tokens[:]) {
        right := parseLess(p) or_return

        op : core.BinOp
        #partial switch tok {
        case .EqualEqual:
            op = .Equal
        case .NotEqual:
            op = .NotEqual
        case: panic("unreachable")
        }

        left = makeExpr(left.loc, core.BinaryExpr{left = left, op = op, right = right}) or_return
    }

    return left, true
}

parseLess :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    left := parseSum(p) or_return

    bin_op_tokens := [?]tokenizer.TokenKind{ .Less, .LessEqual, .Greater, .GreaterEqual }
    for tok, matches := matchesAny(p, bin_op_tokens[:]);
            matches;
            tok, matches = matchesAny(p, bin_op_tokens[:]) {
        right := parseSum(p) or_return

        op : core.BinOp
        #partial switch tok {
        case .Less:
            op = .Less
        case .Greater:
            op = .Greater
        case .LessEqual:
            op = .LessEqual
        case .GreaterEqual:
            op = .GreaterEqual
        case: panic("unreachable")
        }

        left = makeExpr(left.loc, core.BinaryExpr{left = left, op = op, right = right}) or_return
    }

    return left, true
}

parseSum :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    left := parseMult(p) or_return

    bin_op_tokens := [?]tokenizer.TokenKind{ .Plus, .Minus }
    for tok, matches := matchesAny(p, bin_op_tokens[:]);
            matches;
            tok, matches = matchesAny(p, bin_op_tokens[:]) {
        right := parseMult(p) or_return

        op : core.BinOp
        #partial switch tok {
        case .Plus:
            op = .Plus
        case .Minus:
            op = .Minus
        case: panic("unreachable")
        }

        left = makeExpr(left.loc, core.BinaryExpr{left = left, op = op, right = right}) or_return
    }

    return left, true
} 

parseMult :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    left := parseUnary(p) or_return

    bin_op_tokens := [?]tokenizer.TokenKind{ .Star, .Slash }
    for tok, matches := matchesAny(p, bin_op_tokens[:]);
            matches;
            tok, matches = matchesAny(p, bin_op_tokens[:]) {
        right := parseUnary(p) or_return

        op : core.BinOp
        #partial switch tok {
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

parseUnary :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    unary_op_tokens := [?]tokenizer.TokenKind{ .Minus, .Plus }
    if tok, matches := matchesAny(p, unary_op_tokens[:]); matches {
        expr := parseUnary(p) or_return

        op : core.UnaryOp
        #partial switch tok {
        case .Minus:
            op = .Negate
        case .Plus:
            op = .Identity
        case: panic("unreachable")
        }

        expr = makeExpr(expr.loc, core.UnaryExpr{expr = expr, op = op}) or_return
        return expr, true
    }

    return parseCall(p)
}

parseCall :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    callable := parsePrimary(p) or_return

    if matches(p, .LeftBracket) {
        index_expr := parseExpr(p) or_return;
        expect(p, .RightBracket, "expect ']' after index expression") or_return
        return makeExpr(callable.loc, core.IndexExpr{indexable=callable, index=index_expr})
    } else if matches(p, .LeftParen) {
        args : [dynamic]^core.Expr
        for peek(p).kind != .RightParen {
            arg := parseExpr(p) or_return
            append(&args, arg)
            if matches(p, .Comma) {
                continue
            }
        }
        expect(p, .RightParen, "expect ')' after call arguments") or_return
        return makeExpr(callable.loc, core.CallExpr{callable=callable, args=args[:]})
    }
    return callable, true
}

parsePrimary :: proc(p: ^Parser) -> (expr: ^core.Expr, ok: bool) {
    tok := next(p)
    #partial switch tok.kind {
    case .Number:
        return makeExpr(tok.loc, core.LiteralExpr(tok.value.(core.Number)))
    case .Ident:
        return makeExpr(tok.loc, core.IdentExpr{name = tok.value.(string)})
    case .True:
        return makeExpr(tok.loc, core.LiteralExpr(true))
    case .False:
        return makeExpr(tok.loc, core.LiteralExpr(false))
    case .String:
        return makeExpr(tok.loc, core.LiteralExpr(core.String(tok.value.(string))))
    case .LeftBrace:
        values : [dynamic]^core.Expr
        for peek(p).kind != .RightBrace {
            val := parseExpr(p) or_return
            append(&values, val)
            if matches(p, .Comma) {
                continue
            }
        }
        expect(p, .RightBrace, "expect '}' after array values") or_return
        shrink(&values)
        return makeExpr(tok.loc, core.LiteralExpr(core.ArrayExpr{values=values[:]}))
    case .SharpBrace:
        fields: [dynamic]core.StructFieldExpr

        for !matches(p, .RightBrace) {
            maybe_ident_tok := next(p)
            if maybe_ident_tok.kind == .Ident {
                name := maybe_ident_tok.value.(string)
                expect(p, .Equal, "expect '=' after field name") or_return
                value := parseExpr(p) or_return
                append(&fields, core.StructFieldExpr{name = name, value=value})
            } else {
                reportError(p, maybe_ident_tok.loc, "expect struct field name, but got %v", maybe_ident_tok.kind)
                return {}, false
            }

            if matches(p, .Comma) {
                continue
            }
        }

        shrink(&fields)

        return makeExpr(tok.loc, core.StructExpr{fields=fields[:]})
    case:
        if tok.kind == .Eof {
            reportError(p, tok.loc, "unexpected end of file")
        } else {
            reportError(p, tok.loc, "unexpected token '%v'", tok.lexeme)
        }
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

makeBlockStmt :: proc(loc: core.Location, stmts: []^core.Stmt) -> ^core.Stmt {
     block, _ := makeStmt(loc, core.BlockStmt{stmts = stmts[:]})
    return block
}

matches :: proc(p: ^Parser, t: tokenizer.TokenKind) -> bool {
    tok := peek(p)
    if tok.kind == t {
        next(p)
        return true
    }
    return false
}

@(require_results)
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
