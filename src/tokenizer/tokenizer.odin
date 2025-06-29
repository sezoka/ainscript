package tokenizer

import "../core"
import "core:unicode/utf8"
import "core:unicode"
import "core:strconv"
import "core:strings"
import "core:fmt"

TokenKind :: enum {
    Block,
    Builtin,
    Colon,
    Comma,
    Def,
    Do,
    End,
    Eof,
    Equal,
    EqualEqual,
    False,
    For,
    Greater,
    GreaterEqual,
    Ident,
    If,
    LeftBrace,
    LeftParen,
    LeftBracket,
    RightBracket,
    Less,
    LessEqual,
    Minus,
    Bang,
    NotEqual,
    Number,
    Plus,
    Return,
    RightBrace,
    RightParen,
    Semicolon,
    Slash,
    Star,
    String,
    True,
    ColonEqual,
    Dot,
    DotDot,
    While,
    SharpBrace,
    Nil,
}

TokenValue :: union {
    int,
    f64,
    string,
    core.Number,
}

Token :: struct {
    loc: core.Location,
    kind: TokenKind,
    value: TokenValue,
    lexeme: string,
}

makeToken :: proc(t: ^Tokenizer, kind: TokenKind, value: TokenValue = {}) -> (Token, bool) {
    return {
        loc = t.curr_token_loc,
        kind = kind,
        value = value,
        lexeme = getLexeme(t),
    }, true
}

makeKeywordsMap :: proc() -> (keywords: map[string]TokenKind) {
    keywords["if"] = .If
    keywords["def"] = .Def
    keywords["nil"] = .Nil
    keywords["block"] = .Block
    keywords["while"] = .While
    keywords["return"] = .Return
    keywords["builtin"] = .Builtin
    keywords["end"] = .End
    keywords["for"] = .For
    keywords["do"] = .Do
    keywords["true"] = .True
    keywords["false"] = .False
    return keywords
}

Tokenizer :: struct {
    src: string,
    loc: core.Location,
    curr: int,
    had_error: bool,
    curr_token_loc: core.Location,
    curr_token_start: int,
    keywords_map: map[string]TokenKind,
}

tokenize :: proc(src: string, path: string) -> ([]Token, bool) {
    tkz : Tokenizer
    tkz.src = src
    tkz.loc = {1, 1, path}
    tkz.keywords_map = makeKeywordsMap()

    tokens := make([dynamic]Token, context.allocator)

    for tok, ok := nextToken(&tkz); ok; tok, ok = nextToken(&tkz) {
        if tkz.had_error {
            return {}, false
        }
        append(&tokens, tok)
        if tok.kind == .Eof {
            break
        }
    }

    return tokens[:], !tkz.had_error
}

printTokens :: proc(tokens: []Token) {
    for token in tokens {
        fmt.print(token.kind)
        if token.value != {} {
            fmt.print("", token.value)
        }
        fmt.println()
    }
}

peek :: proc(t: ^Tokenizer) -> rune {
    if len(t.src) <= t.curr do return 0
    r, _ := utf8.decode_rune_in_string(t.src[t.curr:])
    if r == utf8.RUNE_ERROR {
        reportError(t, "invalid rune")
        return 0
    }
    return r
}

reportError :: proc(t: ^Tokenizer, fmt: string, args: ..any) {
    t.had_error = true
    strs : [3]string = { core.textColor("tokenizer", .Blue), ": ", fmt }
    str := strings.concatenate(strs[:], allocator=context.temp_allocator)
    core.printErr(t.curr_token_loc, str, ..args)
}

match :: proc(t: ^Tokenizer, r: rune) -> bool {
    if peek(t) == r {
        advance(t)
        return true
    }
    return false
}

advance :: proc(t: ^Tokenizer) -> rune {
    if len(t.src) <= t.curr do return 0
    r, w := utf8.decode_rune_in_string(t.src[t.curr:])
    t.curr += w
    if r == utf8.RUNE_ERROR {
        reportError(t, "invalid rune")
        return 0
    }
    if r == '\n' {
        t.loc.line += 1
        t.loc.col = 1
    } else {
        t.loc.col += 1
    }
    return r
}

peekNext :: proc(t: ^Tokenizer) -> rune {
    if len(t.src) <= t.curr + 1 do return 0

    r, w := utf8.decode_rune_in_string(t.src[t.curr:])
    if r == utf8.RUNE_ERROR {
        reportError(t, "invalid rune")
        return 0
    }

    r, _ = utf8.decode_rune_in_string(t.src[t.curr + w:])
    if r == utf8.RUNE_ERROR {
        reportError(t, "invalid rune")
        return 0
    }

    return r
}

skipWhitespace :: proc(t: ^Tokenizer) {
    for {
        switch peek(t) {
        case '/':
            if peekNext(t) == '/' {
                for peek(t) != '\n' {
                    advance(t)
                }
                advance(t)
            } else {
                return
            }
        case ' ', '\n', '\t', '\r':
            advance(t)
        case: return
        }
    }
}

nextToken :: proc(t: ^Tokenizer) -> (Token, bool) {
    skipWhitespace(t)

    t.curr_token_loc = t.loc
    t.curr_token_start = t.curr

    c := advance(t)

    switch c {
    case '+': return makeToken(t, .Plus)
    case '-': return makeToken(t, .Minus)
    case '*': return makeToken(t, .Star)
    case '/': return makeToken(t, .Slash)
    case '(': return makeToken(t, .LeftParen)
    case ')': return makeToken(t, .RightParen)
    case '{': return makeToken(t, .LeftBrace)
    case '}': return makeToken(t, .RightBrace)
    case '[': return makeToken(t, .LeftBracket)
    case ']': return makeToken(t, .RightBracket)
    case ':': 
        if match(t, '=') {
            return makeToken(t, .ColonEqual)
        } else {
            return makeToken(t, .Colon)
        }
    case '.': 
        if match(t, '.') {
            return makeToken(t, .DotDot)
        } else {
            return makeToken(t, .Dot)
        }
    case ';': return makeToken(t, .Semicolon)
    case '!': 
        if match(t, '=') {
            return makeToken(t, .NotEqual)
        }
        return makeToken(t, .Bang)
    case '#':
        if match(t, '{') {
            return makeToken(t, .SharpBrace)
        }
    case '<':
        if match(t, '=') {
            return makeToken(t, .LessEqual)
        } else {
            return makeToken(t, .Less)
        }
    case '>':
        if match(t, '=') {
            return makeToken(t, .GreaterEqual)
        } else {
            return makeToken(t, .Greater)
        }
    case ',': return makeToken(t, .Comma)
    case '=': 
        if match(t, '=') {
            return makeToken(t, .EqualEqual)
        } else {
            return makeToken(t, .Equal)
        }
    case 0: return makeToken(t, .Eof)
    case: {
        if isIdentifierNameStart(c) {
            return readIdentifier(t)
        }
        if isDigit(c) {
            return readNumber(t)
        }
        if c == '"' {
            return readString(t)
        }
        reportError(t, "unexpected character '%c'", c)
        return {}, false
    }
    }

    return {}, false
}

readString :: proc(t: ^Tokenizer) -> (Token, bool) {
    for peek(t) != '"' && peek(t) != 0 {
        advance(t)
    }
    if peek(t) == 0 {
        reportError(t, "unenclosed string at %d:%d", t.curr_token_loc.line, t.curr_token_loc.col)
        return {}, false
    }
    advance(t);

    string_lex := getLexeme(t)
    string := string_lex[1:len(string_lex)-1]
    
    return makeToken(t, .String, string)
}

readNumber :: proc(t: ^Tokenizer) -> (Token, bool) {
    for isDigit(peek(t)) {
        advance(t)
    }

    is_float := false
    int_part := getLexeme(t)
    float_part := "0"
    if peek(t) == '.' {
        is_float = true
        advance(t)
        start := t.curr
        for isDigit(peek(t)) {
            advance(t)
        }
        float_part = t.src[start:t.curr]
    }

    return makeToken(t, .Number, parseNumber(int_part, float_part))
}

parseNumber :: proc(int_part: string, float_part: string) -> core.Number {
    ip, ip_ok := strconv.parse_i64(int_part)
    fp, fp_ok := strconv.parse_i64(float_part)
    assert(ip_ok && fp_ok)

    cnt := fp
    tens : i64 = 1
    for cnt != 0 {
        cnt /= 10
        tens *= 10
    }

    num := ip * tens + fp
    den := tens

    return {i64(num), i64(den)}
}

readIdentifier :: proc(t: ^Tokenizer) -> (Token, bool) {
    for isIdentifierName(peek(t)) {
        advance(t)
    }

    lex := getLexeme(t)
    keyword, is_keyword := t.keywords_map[lex]
    if is_keyword {
        return makeToken(t, keyword)
    }

    return makeToken(t, .Ident, lex)
}

getLexeme :: proc(t: ^Tokenizer) -> string {
    return t.src[t.curr_token_start:t.curr]
}

isIdentifierNameStart :: proc(c: rune) -> bool {
    return unicode.is_letter(c) || c == '_'
}

isIdentifierName :: proc(c: rune) -> bool {
    return isIdentifierNameStart(c) || isDigit(c)
}

isDigit :: proc(c: rune) -> bool {
    return '0' <= c && c <= '9'
}
