package aininterpreter

import "../core"
import "core:log"
import "core:fmt"
import "core:strings"

Interpreter :: struct {
    scopes: [dynamic]Scope,
    ret_value: Value,
    is_in_func: bool,
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
    case core.WhileStmt:
        for {
            cond_res := interpretExpr(intr, v.cond) or_return
            cond_bool, is_bool := cond_res.(bool)
            if is_bool {
                if cond_bool {
                    interpretStmt(intr, v.body)
                } else {
                    break
                }
            } else {
                reportError(v.cond.loc, "expect bool as conditional value, but got: '%v'", cond_res)
                return false
            }
        }
    case core.RetStmt:
        if v.expr == nil {
            intr.ret_value = makeValue_Nil()
            return true
        } else {
            intr.ret_value = interpretExpr(intr, v.expr) or_return
            return true
        }
    case core.ExprStmt:
        val, ok := interpretExpr(intr, v.expr)
        if !ok do return false
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
            _, is_ret_stmt := stmt.vart.(core.RetStmt)
            if is_ret_stmt do return true;
        }
    case core.FuncStmt:
        func := makeValue_Func(v.name, v.params, v.body, v.is_builtin)
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
            case .Less:
                return makeValue_Bool(a.numeral * b.denominator < b.numeral * a.denominator), true
            case .Greater:
                return makeValue_Bool(a.numeral * b.denominator > b.numeral * a.denominator), true
            case .LessEqual:
                return makeValue_Bool(a.numeral * b.denominator <= b.numeral * a.denominator), true
            case .GreaterEqual:
                return makeValue_Bool(a.numeral * b.denominator >= b.numeral * a.denominator), true
            case .Equal:
                return makeValue_Bool(a.numeral * b.denominator == b.numeral * a.denominator), true
            case .NotEqual:
                return makeValue_Bool(a.numeral * b.denominator != b.numeral * a.denominator), true
            }
        } else {
            reportError(expr.loc, "operator %v expects number operands, but got '%v' and '%v'", e.op, a, b)
        }
    case core.IdentExpr:
        return findVar(intr, expr.loc, e.name)
    case core.LiteralExpr:
        switch lit_expr in e {
        case core.Number:
            return lit_expr, true
        case core.Bool: 
            return lit_expr, true
        }
    case core.CallExpr:
        maybe_func := interpretExpr(intr, e.callable) or_return
        func, is_func := maybe_func.(core.Func)

        if is_func {
            if len(func.params) == len(e.args) {
                pushScope(intr); defer popScope(intr)
                for i in 0..<len(func.params) {
                    arg := interpretExpr(intr, e.args[i]) or_return
                    defineVariable(intr, expr.loc, func.params[i].name, arg)
                }

                if func.is_builtin {
                    if func.name == "print" {
                        val := currScope(intr).vars["val"]
                        printValue(val)
                        return makeValue_Nil(), true
                    } else {
                        log.error("unhandled")
                        return {}, false
                    }
                } else {
                    prev_is_in_func := intr.is_in_func
                    defer intr.is_in_func = prev_is_in_func
                    defer intr.ret_value = makeValue_Nil()
                    intr.is_in_func = true

                    interpretStmt(intr, func.body)

                    return intr.ret_value, true
                }
            } else {
                reportError(expr.loc,
                    "number of function params and passed arguments don't match: '%d' vs '%d'",
                    len(func.params), len(e.args))
                return {}, false
            }
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
