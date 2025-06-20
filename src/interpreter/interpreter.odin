package aininterpreter

import "../core"
import "core:log"
import "core:fmt"
import "core:strings"

Interpreter :: struct {
    scopes: [dynamic]Scope,
}

Scope :: struct {
    vars: map[string]Value,
}

makeScope :: proc() -> Scope {
    return { }
}

pushScope :: proc(intr: ^Interpreter) {
    append(&intr.scopes, makeScope())
}

popScope :: proc(intr: ^Interpreter) {
    pop(&intr.scopes)
}

interpretFile :: proc(file: core.File) {
    intr : Interpreter
    pushScope(&intr)

    for stmt in file.statements {
        interpretStmt(&intr, stmt)
    }
}

currScope :: proc(intr: ^Interpreter) -> ^Scope {
    return &intr.scopes[len(intr.scopes) - 1]
}

findScopeThatHasVar :: proc(intr: ^Interpreter, var_name: string) -> ^Scope {
    for i := len(intr.scopes) - 1; 0 <= i; i -= 1 {
        scope := &intr.scopes[i]
        if var_name in scope.vars {
            return scope
        }
    }
    return nil
}

defineVariable :: proc(intr: ^Interpreter, loc: core.Location, name: string, val: Value) {
    is_exists := findScopeThatHasVar(intr, name) == currScope(intr)
    if is_exists {
        reportError(loc, "variable with name '%s' already exists", name)
    }
    scope := currScope(intr)
    scope.vars[name] = val
}

assignVariable :: proc(intr: ^Interpreter, loc: core.Location, name: string, val: Value) -> bool {
    scope := findScopeThatHasVar(intr, name)
    if scope != nil {
        scope.vars[name] = val
        return true
    } else {
        reportError(loc, "variable with name '%s' is not defined", name)
        return false
    }
}

findVar :: proc(intr: ^Interpreter, loc: core.Location, name: string) -> (Value, bool) {
    scope := findScopeThatHasVar(intr, name)
    if scope != nil {
        return scope.vars[name], true
    } else {
        reportError(loc, "variable with name '%s' is not defined", name)
        return {}, false
    }
}

interpretStmt :: proc(intr: ^Interpreter, stmt: ^core.Stmt) -> bool {
    switch v in stmt.vart {
    case core.ExprStmt:
        val, ok := interpretExpr(intr, v.expr)
        if !ok do return false
        printValue(val)
        return ok
    case core.VarStmt:
        val, ok := interpretExpr(intr, v.value)
        if !ok do return false
        defineVariable(intr, stmt.loc, v.name, val)
    case core.AssignStmt:
        val, ok := interpretExpr(intr, v.value)
        if !ok do return false
        return assignVariable(intr, stmt.loc, v.name, val)
    case core.BlockStmt:
        pushScope(intr); defer popScope(intr)
        for stmt in v.stmts {
            interpretStmt(intr, stmt)
        }
    case core.FuncStmt:
        func := makeValue_Func(v.name, nil, v.body)
        defineVariable(intr, stmt.loc, v.name, func)
    }
    return true
}

interpretExpr :: proc(intr: ^Interpreter, expr: ^core.Expr) -> (val: Value, ok: bool) {
    switch e in expr.vart {
    case core.BinaryExpr:
        left := interpretExpr(intr, e.left) or_return
        right := interpretExpr(intr, e.right) or_return
        a, is_a_num := left.(core.Number)
        b, is_b_num := right.(core.Number)

        num: core.Number
        if is_a_num && is_b_num {
            switch e.op {
            case .Plus:
                num.numeral = a.numeral * b.denominator + b.numeral * a.denominator
                num.denominator = a.denominator * b.denominator
                return makeValue_Number(num), true
            case .Minus:
                num.numeral = a.numeral * b.denominator - b.numeral * a.denominator
                num.denominator = a.denominator * b.denominator
                return makeValue_Number(num), true
            case .Multiply:
                num.numeral = a.numeral * b.numeral
                num.denominator = a.denominator * b.denominator
                return makeValue_Number(num), true
            case .Divide:
                num.numeral = a.numeral * b.denominator
                num.denominator = a.denominator * b.numeral
                return makeValue_Number(num), true
            }
        } else {
            reportError(expr.loc, "operator %v expects number operands, but got '%v' and '%v'", e.op, a, b)
        }
    case core.IdentExpr:
        return findVar(intr, expr.loc, e.name)
    case core.LiteralExpr:
        switch lit_expr in e {
        case core.Number: {
            return lit_expr, true
        }
        }
    case core.CallExpr:
        maybe_func := interpretExpr(intr, e.callable) or_return
        func, is_func := maybe_func.(core.Func)
        if is_func {
            pushScope(intr); defer popScope(intr)
            for stmt in func.body {
                interpretStmt(intr, stmt) or_return
            }
            return makeValue_Nil(), true
        } else {
            reportError(expr.loc, "can call only function expressions, but got '%v'", maybe_func)
            return {}, false
        }
    }

    log.error("unhandled")
    return {}, false
}

reportError :: proc(loc: core.Location, fmt: string, args: ..any) {
    // p.had_error = true
    strs : [2]string = { "Interpreter: ", fmt }
    str := strings.concatenate(strs[:], allocator=context.temp_allocator)
    core.printErr(loc, str, ..args)
}
