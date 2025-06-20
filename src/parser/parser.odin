package ainparser

import "../core"
import "core:fmt"
import "../tokenizer/"
import "core:strings"

Parser :: struct {
    had_error: bool,
    tokens: []tokenizer.Token,
    curr: int,
}

parseFile :: proc(tokens: []tokenizer.Token) -> core.File {
    parser : Parser
    parser.tokens = tokens

    file : core.File
    fmt.println(parseBinary(&parser))
    return file
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
    case:
        reportError(p, tok.loc, "unexpected token '%v'", tok.lexeme)
        return {}, false
    }
    return {}, false
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
