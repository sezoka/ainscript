package aininterpreter

import "../core"
import "core:log"
import "core:fmt"
import "core:time"
import "core:strings"

Interpreter :: struct {
    // scopes: [dynamic]core.Scope,
    ret_value: core.Value,
    is_in_func: bool,
    should_return: bool,
    curr_scope: ^core.Scope,
}

makeScope :: proc(parent: ^core.Scope) -> ^core.Scope {
    scope := new(core.Scope)
    scope.parent = parent
    return scope
}

deleteScope :: proc(s: ^core.Scope) {
    delete(s.vars)
    free(s)
}

pushScope :: proc(intr: ^Interpreter) {
    scope := makeScope(intr.curr_scope)
    scope.ref_count = 1
    intr.curr_scope = scope
}

popScope :: proc(intr: ^Interpreter) {
    parent := intr.curr_scope.parent
    assert(intr.curr_scope.ref_count != 0)
    if intr.curr_scope.ref_count == 1 {
        intr.curr_scope.ref_count = 0
        deleteScope(intr.curr_scope)
    }
    intr.curr_scope = parent
}

interpretFile :: proc(file: core.File) {
    intr : Interpreter
    intr.ret_value = makeValue_Nil()
    pushScope(&intr)

    for stmt in file.statements {
        if !interpretStmt(&intr, stmt) {
            return
        }
    }
}

currScope :: proc(intr: ^Interpreter) -> ^core.Scope {
    return intr.curr_scope
}

findScopeThatHasVar :: proc(intr: ^Interpreter, var_name: string) -> ^core.Scope {
    for scope := intr.curr_scope; scope != nil; scope = scope.parent {
        if var_name in scope.vars {
            return scope
        }
    }
    return nil
}

defineVariable :: proc(intr: ^Interpreter, loc: core.Location, name: string, val: core.Value) -> bool {
    is_exists := findScopeThatHasVar(intr, name) == currScope(intr)
    if is_exists {
        reportError(loc, "variable with name '%s' already exists", name)
        return false
    }
    scope := currScope(intr)
    scope.vars[name] = val
    return true
}

assignVariable :: proc(intr: ^Interpreter, loc: core.Location, name: string, val: core.Value) -> bool {
    scope := findScopeThatHasVar(intr, name)
    if scope != nil {
        scope.vars[name] = val
        return true
    } else {
        reportError(loc, "variable with name '%s' is not defined", name)
        return false
    }
}

findVar :: proc(intr: ^Interpreter, loc: core.Location, name: string) -> (core.Value, bool) {
    scope := findScopeThatHasVar(intr, name)
    if scope != nil {
        return scope.vars[name], true
    } else {
        reportError(loc, "variable with name '%s' is not defined", name)
        return {}, false
    }
}

@(require_results)
interpretStmt :: proc(intr: ^Interpreter, stmt: ^core.Stmt) -> bool {
    switch v in stmt.vart {
    case core.IfStmt:
        cond_res := interpretExpr(intr, v.cond) or_return
        cond_bool, is_bool := cond_res.(bool)
        if is_bool {
            if cond_bool {
                interpretStmt(intr, v.body) or_return
            } else {
                break
            }
        } else {
            reportError(v.cond.loc, "expect bool as conditional value, but got: '%v'", cond_res)
            return false
        }
    case core.WhileStmt:
        for {
            cond_res := interpretExpr(intr, v.cond) or_return
            cond_bool, is_bool := cond_res.(bool)
            if is_bool {
                if cond_bool {
                    interpretStmt(intr, v.body) or_return
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
            intr.should_return = true
            return true
        } else {
            intr.ret_value = interpretExpr(intr, v.expr) or_return
            intr.should_return = true
            return true
        }
    case core.ExprStmt:
        interpretExpr(intr, v.expr) or_return
    case core.VarStmt:
        val, ok := interpretExpr(intr, v.value)
        if !ok do return false
        defineVariable(intr, stmt.loc, v.name, val) or_return
    case core.AssignStmt:
        val := interpretExpr(intr, v.value) or_return
        return assignVariable(intr, stmt.loc, v.name, val)
    case core.BlockStmt:
        pushScope(intr); defer popScope(intr)

        for stmt in v.stmts {
            interpretStmt(intr, stmt) or_return
            if intr.should_return do return true
        }
    case core.FuncStmt:
        func := makeValue_Func(v.name, v.params, v.body, currScopeInc(intr), v.is_builtin)
        defineVariable(intr, stmt.loc, v.name, func) or_return
    }
    return true
}

currScopeInc :: proc(intr: ^Interpreter) -> ^core.Scope {
    scope := currScope(intr)
    scope.ref_count += 1
    return scope
}

interpretExpr :: proc(intr: ^Interpreter, expr: ^core.Expr) -> (val: core.Value, ok: bool) {
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
            return {}, false
        }
    case core.IdentExpr:
        return findVar(intr, expr.loc, e.name)
    case core.LiteralExpr:
        switch lit_expr in e {
        case core.String:
            return lit_expr, true 
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
                // eval args
                args := make([dynamic]core.Value, len(func.params))
                defer delete(args)
                for i in 0..<len(func.params) {
                    arg := interpretExpr(intr, e.args[i]) or_return
                    args[i] = arg
                }

                // create new scope
                prev_scope := intr.curr_scope;
                defer intr.curr_scope = prev_scope
                intr.curr_scope = func.scope
                pushScope(intr); defer popScope(intr)

                // define params
                for arg, i in args {
                    defineVariable(intr, expr.loc, func.params[i].name, arg)
                }

                if func.is_builtin {
                    if func.name == "print" {
                        val := currScope(intr).vars["val"]
                        printValue(val)
                        return makeValue_Nil(), true
                    } else if func.name == "timestamp" {
                        numeral : i64 = time.to_unix_nanoseconds(time.now())
                        return core.Number{numeral, 1}, true
                    } else {
                        log.error("unhandled")
                        return {}, false
                    }
                } else {
                    prev_is_in_func := intr.is_in_func
                    intr.should_return = false
                    defer intr.should_return = false
                    defer intr.is_in_func = prev_is_in_func
                    intr.is_in_func = true

                    interpretStmt(intr, func.body) or_return

                    ret_val := intr.ret_value
                    intr.ret_value = makeValue_Nil()

                    return ret_val, true
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

printScopes :: proc(intr: ^Interpreter) {
    fmt.println("BEGIN")
    for scope := intr.curr_scope; scope != nil; scope = scope.parent {
        for key, value in scope.vars {
            fmt.println("  ", key)
        }
    }
    fmt.println("END")
}

reportError :: proc(loc: core.Location, fmt: string, args: ..any) {
    // p.had_error = true
    strs : [2]string = { "Interpreter: ", fmt }
    str := strings.concatenate(strs[:], allocator=context.temp_allocator)
    core.printErr(loc, str, ..args)
}
