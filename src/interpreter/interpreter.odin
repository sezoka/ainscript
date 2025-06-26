package aininterpreter

import "../core"
import "../ffi"
import "core:log"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:dynlib"

Interpreter :: struct {
    // scopes: [dynamic]core.Scope,
    ret_value: core.Value,
    is_in_func: bool,
    should_return: bool,
    curr_scope: ^core.Scope,
    ffi_func_decls: [dynamic]FFIFuncDecl,
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
        reportError(loc, "variable with name '%s' already exists", name) or_return
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
        return reportError(loc, "variable with name '%s' is not defined", name)
    }
}

findVar :: proc(intr: ^Interpreter, loc: core.Location, name: string) -> (val: core.Value, ok: bool) {
    scope := findScopeThatHasVar(intr, name)
    if scope != nil {
        return scope.vars[name], true
    } else {
        reportError(loc, "variable with name '%s' is not defined", name) or_return
    }
    return
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
            reportError(v.cond.loc, "expect bool as conditional value, but got: '%v'", cond_res) or_return
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
                reportError(v.cond.loc, "expect bool as conditional value, but got: '%v'", cond_res) or_return
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
    case core.StructExpr:
        fields := make([]core.StructField, len(e.fields))
        for i in 0..<len(fields) {
            fields[i].name = e.fields[i].name
            fields[i].value = interpretExpr(intr, e.fields[i].value) or_return
        }
        return makeValue_Struct(fields), true
    case core.UnaryExpr:
        val := interpretExpr(intr, e.expr) or_return
        switch e.op {
        case .Identity:
            num, is_num := val.(core.Number)
            if is_num {
                return num, true
            } else {
                reportError(expr.loc, "can use unary expession '+' only on numbers") or_return
            }
        case .Negate:
            num, is_num := val.(core.Number)
            if is_num {
                negated := num
                num.numeral = -num.numeral
                return makeValue_Number(num), true
            } else {
                reportError(expr.loc, "can use unary expession '-' only on numbers") or_return
            }
        }
    case core.IndexExpr:
        index_val := interpretExpr(intr, e.index) or_return
        number, is_number := index_val.(core.Number)
        if is_number {
            index := number.numeral / number.denominator
            if 0 <= index {
                indexable := interpretExpr(intr, e.indexable) or_return
                arr, is_arr := indexable.(core.Array)
                if is_arr {
                    if int(index) < len(arr.values) {
                        indexed_value := arr.values[index]
                        return indexed_value, true
                    } else {
                        reportError(e.index.loc, "index out of bounds: array length == '%v', index == '%v'", len(arr.values), index) or_return
                    }
                } else {
                    reportError(e.indexable.loc, "can index only inside arrays") or_return
                }
            } else {
                reportError(e.index.loc, "index should be a positive number, but got '%d'", index) or_return
            }
        } else {
            reportError(e.index.loc, "index expression should evaluate to a number, but got '%v'", index_val) or_return
        }
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
            reportError(expr.loc, "operator %v expects number operands, but got '%v' and '%v'", e.op, a, b) or_return
        }
    case core.IdentExpr:
        return findVar(intr, expr.loc, e.name)
    case core.LiteralExpr:
        switch lit_expr in e {
        case core.ArrayExpr:
            values : [dynamic]core.Value
            for value in lit_expr.values {
                append(&values, interpretExpr(intr, value) or_return)
            }
            return makeValue_Array(values), true
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
            has_rest_param := len(func.params) != 0 && func.params[len(func.params)-1].is_rest
            if len(func.params) == len(e.args) || (has_rest_param && len(func.params) <= len(e.args)) {
                // eval args
                args := make([dynamic]core.Value, len(func.params))
                defer delete(args)

                params_len := has_rest_param ? len(func.params) - 1 : len(func.params)
                for i in 0..<params_len {
                    arg := interpretExpr(intr, e.args[i]) or_return
                    args[i] = arg
                }
                if has_rest_param {
                    rest_args_len := len(e.args) - params_len
                    rest_args := make([dynamic]core.Value, rest_args_len)
                    for i in 0..<rest_args_len {
                        arg := interpretExpr(intr, e.args[i + params_len]) or_return
                        rest_args[i] = arg
                    }
                    rest_arr := makeValue_Array(rest_args)
                    args[len(func.params) - 1] = rest_arr
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
                    if func.name == "println" || func.name == "print" {
                        val := currScope(intr).vars["val"]
                        val_arr := val.(core.Array)
                        for val, i in val_arr.values {
                            printValue(val)
                            if i != len(val_arr.values) - 1 {
                                fmt.print(" ")
                            }
                        }
                        if func.name == "println" {
                            fmt.println()
                        }
                        return makeValue_Nil(), true
                    } else if func.name == "timestamp" {
                        numeral : i64 = time.to_unix_nanoseconds(time.now())
                        return core.Number{numeral, 1}, true
                    } else  if func.name == "loadLibrary" {
                        path := currScope(intr).vars["path"]
                        path_str, is_str := path.(core.String)
                        if is_str {
                            lib := loadLibrary(e.callable.loc, string(path_str)) or_return
                            return makeValue_Pointer(rawptr(lib)), true
                        } else {
                            reportError(e.callable.loc, "builtin 'loadLibrary' expects library path as string") or_return
                        }
                    } else  if func.name == "unloadLibrary" {
                        lib_ptr := currScope(intr).vars["lib_ptr"]
                        ptr, is_ptr := lib_ptr.(rawptr)
                        if is_ptr {
                            dynlib.unload_library(dynlib.Library(ptr)) or_return
                            return makeValue_Nil(), true
                        } else {
                            reportError(e.callable.loc, "builtin 'unloadLibrary' expects library pointer") or_return
                        }
                    } else if func.name == "loadLibraryFunc" {
                        return handleLoadLibraryFuncBuiltin(intr, e)
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
                if has_rest_param {
                    reportError(expr.loc,
                        "number of function params and passed arguments don't match: func: '%d' or more; args: '%d'",
                        len(func.params), len(e.args)) or_return
                } else {
                    reportError(expr.loc,
                        "number of function params and passed arguments don't match: func: '%d'; args: '%d'",
                        len(func.params), len(e.args)) or_return
                }
            }
        } else {
            reportError(expr.loc, "can call only function expressions, but got '%v'", maybe_func) or_return
        }
    }

    log.error("unhandled")
    return {}, false
}

handleLoadLibraryFuncBuiltin :: proc(intr: ^Interpreter, call: core.CallExpr) -> (func_handle: core.Value, ok: bool) {
    lib_ptr_val := currScope(intr).vars["lib_ptr"]
    lib_ptr := checkType(intr, call.args[0].loc, lib_ptr_val, rawptr, "1 argument should be library handle") or_return
    ret_type_val := currScope(intr).vars["ret_type"]
    ret_type := checkType(intr, call.args[1].loc, ret_type_val, core.String, "2 argument should be string representing type of return value") or_return
    name_val := currScope(intr).vars["name"]
    name := checkType(intr, call.args[2].loc, name_val, core.String, "3 argument should be string representing name of function") or_return
    params := currScope(intr).vars["params"].(core.Array)

    ffi_ret_type := ainsTypeStringToFFIType(string(ret_type), call.args[1].loc) or_return
    ffi_params := make([dynamic]^ffi.ffi_type, len(params.values))
    as_ffi_params := make([dynamic]core.ValueType, len(params.values))

    func_addr, found_func := dynlib.symbol_address(dynlib.Library(lib_ptr), string(name))
    if found_func {
        for param, i in params.values {
            param_val := checkType(intr, call.args[3].loc, param, core.String, "return type should be string") or_return
            ffi_param := ainsTypeStringToFFIType(string(param_val), call.args[3].loc) or_return
            ffi_params[i] = ffi_param
            as_ffi_params[i] = core.valueToValueType(param_val)
        }

        cif : ffi.ffi_cif
        if ffi.prep_cif(&cif, .FFI_DEFAULT_ABI, u32(len(params.values)), ffi_ret_type, raw_data(ffi_params)) == .FFI_OK {
            ffi_func_decl : FFIFuncDecl
            ffi_func_decl.cif = cif
            ffi_func_decl.func_ptr = func_addr
            ffi_func_decl.ret_type = ffi_ret_type
            ffi_func_decl.param_types = ffi_params[:]
            ffi_func_decl.as_param_types = as_ffi_params[:]
            append(&intr.ffi_func_decls, ffi_func_decl)
            func_idx := len(intr.ffi_func_decls) - 1
            return makeValue_Number({i64(func_idx), 1}), true
        } else {
            reportError(call.callable.loc, "failed preparing ffi call") or_return
        }
    }

    return {}, true
}

checkType :: proc(intr: ^Interpreter, loc: core.Location, value: core.Value, $T: typeid, msg: string) -> (val: T, ok: bool) {
    inner_type, is_match := value.(T)
    if is_match {
        return inner_type, true
    } else {
        reportError(loc, "%s, but got '%v'", msg, value) or_return
        return {}, false
    }
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

@(require_results)
reportError :: proc(loc: core.Location, fmt: string, args: ..any) -> bool {
    // p.had_error = true
    strs : [2]string = { "Interpreter: ", fmt }
    str := strings.concatenate(strs[:], allocator=context.temp_allocator)
    core.printErr(loc, str, ..args)
    return false
}
