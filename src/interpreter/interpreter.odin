package aininterpreter

import "../core"
import "../ffi"
import "core:log"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:dynlib"
import "core:path/filepath"
import "../tokenizer"
import "../parser"
import "core:os/os2"

void :: struct {}

FileState :: struct {
    ast: core.File,
    exe_ctx: ExecContext,
}

ExecContext :: struct {
    curr_scope: ^core.Scope,
    root_scope: ^core.Scope,
    ret_value: core.Value,
    is_in_func: bool,
    should_return: bool,
    curr_file_path: string,
}

Interpreter :: struct {
    exe_ctx: ^ExecContext,

    ffi_func_decls: [dynamic]FFIFuncDecl,
    scopes: map[^core.Scope]void,
    heap_allocated_values: map[rawptr]core.Value,
    functions: map[^core.Func]void,
    marked_things: map[rawptr]void,
    call_stack: [dynamic]CallStackFrame,
    prev_alloc_count: uint,
    files: map[string]^FileState,
    prelude_scope: ^core.Scope,
    ain_directory: string,
}


CallStackFrame :: struct {
    scope: ^core.Scope,
    expr: ^core.Expr,
}

makeScope :: proc(intr: ^Interpreter, parent: ^core.Scope) -> ^core.Scope {
    scope := new(core.Scope)
    scope.parent = parent
    intr.scopes[scope] = {}
    return scope
}

deleteScope :: proc(intr: ^Interpreter, s: ^core.Scope) {
    delete_key(&intr.scopes, s)
    delete(s.vars)
    free(s)
}

pushScope :: proc(intr: ^Interpreter) {
    scope := makeScope(intr, intr.exe_ctx.curr_scope)
    intr.exe_ctx.curr_scope = scope
}

popScope :: proc(intr: ^Interpreter) {
    intr.exe_ctx.curr_scope = intr.exe_ctx.curr_scope.parent
}

makeFileState :: proc(intr: ^Interpreter, file: core.File) -> ^FileState {
    state := new(FileState)
    state.ast = file
    state.exe_ctx.curr_file_path = file.path
    state.exe_ctx.curr_scope = intr.prelude_scope
    return state
}

addFileState :: proc(intr: ^Interpreter, file: core.File) -> ^FileState {
    file_state := makeFileState(intr, file)
    intr.files[file.path] = file_state
    return file_state
}

interpretMainFile :: proc(file: core.File) -> bool {
    intr : Interpreter
    exe_path, err := os2.get_executable_path(context.temp_allocator)
    assert(err == nil)
    intr.ain_directory = filepath.dir(exe_path)

    intr.exe_ctx = &addFileState(&intr, file).exe_ctx

    prelude_path, prelude_path_ok := core.relToAbsFilePath(
        context.allocator,
        intr.ain_directory,
        "../core/prelude.ais"
    )
    parseAndInterpretFile(&intr, prelude_path);
    intr.prelude_scope = intr.exe_ctx.curr_scope

    return interpretFile(&intr, file)
}

@(require_results)
interpretFile :: proc(intr: ^Interpreter, file: core.File) -> bool {
    prev_ctx := intr.exe_ctx; defer intr.exe_ctx = prev_ctx
    intr.exe_ctx = &intr.files[file.path].exe_ctx

    pushScope(intr)
    // append(&intr.call_stack, CallStackFrame{scope = intr.exe_ctx.curr_scope, expr = {}})

    intr.exe_ctx.root_scope = intr.exe_ctx.curr_scope

    for stmt in file.statements {
        if !interpretStmt(intr, stmt) {
            return false
        }
    }
    return true
}

parseAndInterpretFile :: proc(intr: ^Interpreter, path: string, loc: Maybe(core.Location) = nil) -> (ok: bool) {
    pushScope(intr)
    // append(&intr.call_stack, intr.exe_ctx.curr_scope)

    src, read_ok := core.readFile(path, loc)
    if !read_ok do return

    tokens, tokenize_ok := tokenizer.tokenize(string(src), path)
    if !tokenize_ok do return

    file_ast, parse_ok := parser.parseFile(tokens, path, string(src))
    if !parse_ok do return

    for stmt in file_ast.statements {
        if !interpretStmt(intr, stmt) {
            return
        }
    }

    return true
}

currScope :: proc(intr: ^Interpreter) -> ^core.Scope {
    return intr.exe_ctx.curr_scope
}

findScopeThatHasVar :: proc(intr: ^Interpreter, var_name: string) -> ^core.Scope {
    for scope := intr.exe_ctx.curr_scope; scope != nil; scope = scope.parent {
        if var_name in scope.vars {
            return scope
        }
    }
    return nil
}

@(require_results)
defineVariable :: proc(intr: ^Interpreter, loc: core.Location, name: string, val: core.Value) -> bool {
    is_exists := findScopeThatHasVar(intr, name) == currScope(intr)
    if is_exists {
        reportError(intr, loc, "variable with name '%s' already exists", name) or_return
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
        return reportError(intr, loc, "variable with name '%s' is not defined", name)
    }
}

findVar :: proc(intr: ^Interpreter, loc: core.Location, name: string) -> (val: core.Value, ok: bool) {
    scope := findScopeThatHasVar(intr, name)
    if scope != nil {
        return scope.vars[name], true
    } else {
        reportError(intr, loc, "variable with name '%s' is not defined", name) or_return
    }
    return
}

@(require_results)
interpretStmt :: proc(intr: ^Interpreter, stmt: ^core.Stmt) -> bool {
    if intr.prev_alloc_count + 2000 < len(intr.heap_allocated_values) + len(intr.scopes) {
        // fmt.println("GC START:")
        // fmt.printfln("allocated values: %d\nallocated scopes: %d\nallocated funcs: %d", len(intr.heap_allocated_values), len(intr.scopes), len(intr.functions))
        runGC(intr)
        // fmt.println("GC END:")
        // fmt.printfln("allocated values: %d\nallocated scopes: %d\nallocated funcs: %d", len(intr.heap_allocated_values), len(intr.scopes), len(intr.functions))
        intr.prev_alloc_count = len(intr.heap_allocated_values) + len(intr.scopes)
    }

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
            reportError(intr, v.cond.loc, "expect bool as conditional value, but got: '%s'", formatType(cond_res)) or_return
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
                reportError(intr, v.cond.loc, "expect bool as conditional value, but got: '%s'", formatType(cond_res)) or_return
            }
        }
    case core.RetStmt:
        if intr.exe_ctx.is_in_func {
            if v.expr == nil {
                intr.exe_ctx.ret_value = makeValue_Nil()
                intr.exe_ctx.should_return = true
                return true
            } else {
                intr.exe_ctx.ret_value = interpretExpr(intr, v.expr) or_return
                intr.exe_ctx.should_return = true
                return true
            }
        } else {
            reportError(intr, stmt.loc, "can't return from top-level code") or_return
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
            if intr.exe_ctx.should_return do return true
        }
    case core.FuncStmt:
        func := makeValue_Func(intr, v.name, v.params, v.body, intr.exe_ctx.curr_scope, v.is_builtin)
        defineVariable(intr, stmt.loc, v.name, func) or_return
    }
    return true
}

interpretExpr :: proc(intr: ^Interpreter, expr: ^core.Expr) -> (val: core.Value, ok: bool) {
    switch e in expr.vart {
    case core.AccessExpr:
        accessable := interpretExpr(intr, e.expr) or_return
        strct, is_struct := accessable.(^core.Struct)
        module, is_module := accessable.(core.Module)
        if is_struct {
            for field in strct.fields {
                if field.name == e.field_name {
                    return field.value, true
                }
            }
            reportError(
                intr, expr.loc, "field '%s' was not found in struct '%s'",
                e.field_name,
                formatType(accessable)
            ) or_return
        } else if is_module {
            file_state := intr.files[string(module)]
            if e.field_name in file_state.exe_ctx.root_scope.vars {
                return file_state.exe_ctx.root_scope.vars[e.field_name]
            } else {
                reportError(
                    intr, expr.loc, "variable '%s' was not found in module '%s'",
                    e.field_name,
                    formatType(accessable)
                ) or_return
            }
        } else {
            reportError(
                intr, expr.loc, "can use '.' operator only to access struct fields, but accessing '%s'",
                formatType(accessable)
            ) or_return
        }
    case core.StructExpr:
        fields := make([]core.StructField, len(e.fields))
        for i in 0..<len(fields) {
            fields[i].name = e.fields[i].name
            fields[i].value = interpretExpr(intr, e.fields[i].value) or_return
        }
        return makeValue_Struct(intr, fields), true
    case core.UnaryExpr:
        val := interpretExpr(intr, e.expr) or_return
        switch e.op {
        case .Identity:
            num, is_num := val.(core.Number)
            if is_num {
                return num, true
            } else {
                reportError(intr, expr.loc, "can use unary expession '+' only on numbers") or_return
            }
        case .Minus:
            num, is_num := val.(core.Number)
            if is_num {
                negated := num
                num.numeral = -num.numeral
                return makeValue_Number(num), true
            } else {
                reportError(intr, expr.loc, "can use unary expession '-' only on numbers") or_return
            }
        case .Negate:
            b, is_bool := val.(core.Bool)
            if is_bool {
                return makeValue_Bool(!b), true
            } else {
                reportError(intr, expr.loc, "can use unary expession '!' only on booleans") or_return
            }
        }
    case core.IndexExpr:
        index_val := interpretExpr(intr, e.index) or_return
        number, is_number := index_val.(core.Number)
        if is_number {
            index := number.numeral / number.denominator
            if 0 <= index {
                indexable := interpretExpr(intr, e.indexable) or_return
                arr, is_arr := indexable.(^core.Array)
                if is_arr {
                    if int(index) < len(arr.values) {
                        indexed_value := arr.values[index]
                        return indexed_value, true
                    } else {
                        reportError(intr, e.index.loc, "index out of bounds: array length == '%v', index == '%v'", len(arr.values), index) or_return
                    }
                } else {
                    reportError(intr, e.indexable.loc, "can index only inside arrays") or_return
                }
            } else {
                reportError(intr, e.index.loc, "index must be a positive number, but got '%s'", formatValue(index_val)) or_return
            }
        } else {
            reportError(intr, e.index.loc, "index expression must evaluate to a number, but got '%s'", formatValue(index_val)) or_return
        }
    case core.BinaryExpr:
        left := interpretExpr(intr, e.left) or_return
        right := interpretExpr(intr, e.right) or_return

        #partial switch e.op {
        case .Equal:
            return makeValue_Bool(valuesEql(left, right)), true
        case .NotEqual:
            return makeValue_Bool(!valuesEql(left, right)), true
        case:
        }

        a, is_a_num := left.(core.Number)
        b, is_b_num := right.(core.Number)

        num: core.Number
        if is_a_num && is_b_num {
            #partial switch e.op {
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
                if b.numeral == 0 {
                    reportError(
                        intr,
                        expr.loc,
                        "division by zero",
                    ) or_return

                } else {
                    return makeValue_Number(num), true
                }
            case .Less:
                return makeValue_Bool(a.numeral * b.denominator < b.numeral * a.denominator), true
            case .Greater:
                return makeValue_Bool(a.numeral * b.denominator > b.numeral * a.denominator), true
            case .LessEqual:
                return makeValue_Bool(a.numeral * b.denominator <= b.numeral * a.denominator), true
            case .GreaterEqual:
                return makeValue_Bool(a.numeral * b.denominator >= b.numeral * a.denominator), true
            case:
            }
        } else {
            reportError(
                intr,
                expr.loc,
                "operator '%v' expects number operands, but got '%s' and '%s'",
                e.op,
                formatType(a),
                formatType(b)
            ) or_return
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
            return makeValue_Array(intr, values), true
        case core.Nil:
            return lit_expr, true
        case core.String:
            return lit_expr, true 
        case core.Number:
            return lit_expr, true
        case core.Bool: 
            return lit_expr, true
        }
    case core.CallExpr:
        maybe_func := interpretExpr(intr, e.callable) or_return
        func, is_func := maybe_func.(^core.Func)

        if is_func {
            has_rest_param := len(func.params) != 0 && func.params[len(func.params)-1].is_rest
            if len(func.params) == len(e.args) || (has_rest_param && len(func.params)-1 <= len(e.args)) {
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
                    rest_arr := makeValue_Array(intr, rest_args)
                    args[len(func.params) - 1] = rest_arr
                }


                // create new scope
                append(&intr.call_stack, CallStackFrame{scope = intr.exe_ctx.curr_scope, expr = expr})
                defer pop(&intr.call_stack)

                prev_scope := intr.exe_ctx.curr_scope
                defer intr.exe_ctx.curr_scope = prev_scope
                intr.exe_ctx.curr_scope = func.scope

                pushScope(intr); defer popScope(intr)

                // define params
                for arg, i in args {
                    defineVariable(intr, expr.loc, func.params[i].name, arg) or_return
                }

                if func.is_builtin {
                    return handleBuiltins(intr, expr.loc, e, func)
                } else {
                    prev_is_in_func := intr.exe_ctx.is_in_func
                    intr.exe_ctx.should_return = false
                    defer intr.exe_ctx.should_return = false
                    defer intr.exe_ctx.is_in_func = prev_is_in_func
                    intr.exe_ctx.is_in_func = true

                    interpretStmt(intr, func.body) or_return

                    ret_val := intr.exe_ctx.ret_value
                    intr.exe_ctx.ret_value = makeValue_Nil()

                    return ret_val, true
                }
            } else {
                if has_rest_param {
                    reportError(intr, expr.loc,
                        "number of function params and passed arguments don't match: func: '%d' or more; args: '%d'",
                        len(func.params), len(e.args)) or_return
                } else {
                    reportError(intr, expr.loc,
                        "number of function params and passed arguments don't match: func: '%d'; args: '%d'",
                        len(func.params), len(e.args)) or_return
                }
            }
        } else {
            reportError(intr, expr.loc, "can call only function expressions, but got '%s'", formatType(maybe_func)) or_return
        }
    }

    log.error("unhandled")
    return {}, false
}

handleBuiltins :: proc(intr: ^Interpreter, loc: core.Location, call: core.CallExpr, func: ^core.Func) -> (ret_val: core.Value, ok: bool) {
    if func.name == "println" || func.name == "print" {
        val := currScope(intr).vars["val"]
        val_arr := val.(^core.Array)
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
            lib := loadLibrary(intr, call.callable.loc, string(path_str)) or_return
            return makeValue_Pointer(rawptr(lib)), true
        } else {
            reportError(intr, call.callable.loc, "builtin 'loadLibrary' expects library path as string") or_return
        }
    } else if func.name == "unloadLibrary" {
        lib_ptr := currScope(intr).vars["lib_ptr"]
        ptr, is_ptr := lib_ptr.(rawptr)
        if is_ptr {
            dynlib.unload_library(dynlib.Library(ptr)) or_return
            return makeValue_Nil(), true
        } else {
            reportError(intr, call.callable.loc, "builtin 'unloadLibrary' expects library pointer") or_return
        }
    } else if func.name == "prepareLibraryFunc" {
        return handlePrepareLibraryFuncBuiltin(intr, call)
    } else if func.name == "callLibraryFunc" {
        return handleCallLibraryFuncBuiltin(intr, call)
    } else if func.name == "import" {
        return handleImportBuiltin(intr, call)
    } else if func.name == "error" {
        path_val := currScope(intr).vars["msg"]
        err_msg := checkType(
            intr,
            loc,
            path_val,
            core.String,
            "error function expects error message"
        ) or_return
        reportError(intr, loc, err_msg) or_return
        return {}, false
    }

    log.error("unhandled")
    return {}, false
}

handleImportBuiltin :: proc(intr: ^Interpreter, call: core.CallExpr) -> (ret_val: core.Value, ok: bool) {
    path_val := currScope(intr).vars["path"]
    path_str := checkType(intr, call.args[0].loc, path_val, core.String, "import expects path string") or_return
    func_location := call.callable.loc.file
    path, path_ok := core.relToAbsFilePath(context.allocator, filepath.dir(func_location), path_str) 
    if path_ok {
        if path in intr.files {
            return makeValue_Module(path), true
        } else {
            src, ok := core.readFile(path, call.callable.loc)
            if !ok do return

            tokens, tokenize_ok := tokenizer.tokenize(string(src), path)
            if !tokenize_ok do return

            file_ast, parse_ok := parser.parseFile(tokens, path, string(src))
            if !parse_ok do return

            addFileState(intr, file_ast)
            interpretFile(intr, file_ast) or_return

            return makeValue_Module(path), true
        }
    } else {
        reportError(intr, call.args[0].loc, "invalid file path") or_return
        return {}, false
    }
}

handleCallLibraryFuncBuiltin :: proc(intr: ^Interpreter, call: core.CallExpr) -> (ret_val: core.Value, ok: bool) {
    func_handle_val := currScope(intr).vars["func_handle"]
    params_val := currScope(intr).vars["params"]

    func_handle := checkType(intr, call.args[0].loc, func_handle_val, core.Number, "1 argument must be func handle") or_return
    params := checkType(intr, call.args[1].loc, params_val, ^core.Array, "2 argument must be library handle") or_return


    if int(func_handle.numeral) < len(intr.ffi_func_decls) && func_handle.denominator == 1 {
        func_decl := intr.ffi_func_decls[func_handle.numeral]
        converted_params: [100]rawptr
        free_all(context.temp_allocator)
        if len(func_decl.param_types) == len(params.values) {
            for param, i in params.values {
                converted_params[i] = convertASValueToCValuePtr(
                    intr,
                    call.args[1].loc,
                    param,
                    func_decl.param_types[i],
                ) or_return
            }
            ret_value_buff: [256]u8 
            ffi.call(&func_decl.cif, func_decl.func_ptr, &ret_value_buff, auto_cast &converted_params);
            ret_value := convertCValueToASValue(intr, call.callable.loc, &ret_value_buff, func_decl.ret_type) or_return
            return ret_value, true;
        } else {
            reportError(intr, call.callable.loc,
                "number of function params and passed arguments don't match: func: '%d' args: '%d'",
                len(func_decl.param_types), len(params.values)) or_return
        }
    } else {
        reportError(intr, call.args[0].loc, "invalid func handle") or_return
    }

    return {}, false
}

handlePrepareLibraryFuncBuiltin :: proc(intr: ^Interpreter, call: core.CallExpr) -> (func_handle: core.Value, ok: bool) {
    lib_ptr_val := currScope(intr).vars["lib_ptr"]
    lib_ptr := checkType(intr, call.args[0].loc, lib_ptr_val, rawptr, "1 argument must be library handle") or_return
    ret_type_val := currScope(intr).vars["ret_type"]
    ret_type := checkType(intr, call.args[1].loc, ret_type_val, core.String, "2 argument must be string representing type of return value") or_return
    name_val := currScope(intr).vars["name"]
    name := checkType(intr, call.args[2].loc, name_val, core.String, "3 argument must be string representing name of function") or_return
    params := currScope(intr).vars["params"].(^core.Array)

    ffi_ret_type := ainsTypeStringToFFIType(intr, string(ret_type), call.args[1].loc) or_return

    ffi_params := make([dynamic]^ffi.ffi_type, len(params.values))

    func_addr, found_func := dynlib.symbol_address(dynlib.Library(lib_ptr), string(name))
    if found_func {
        for param, i in params.values {
            param_str, is_string_param := param.(core.String)
            param_struct, is_struct_param := param.(^core.Struct)
            if is_struct_param || is_string_param {
                if is_string_param {
                    ffi_param := ainsTypeStringToFFIType(intr, string(param_str), call.args[3].loc) or_return
                    ffi_params[i] = ffi_param
                } else {
                    ffi_param := ainsStructTypeToFFIStructType(intr, param_struct, call.args[3].loc) or_return
                    ffi_params[i] = ffi_param
                }
            } else {
                reportError(intr, call.args[3].loc, "ffi param type must be string or struct, but got '%s'", formatType(param)) or_return
            }

        }

        cif : ffi.ffi_cif
        if ffi.prep_cif(&cif, .FFI_DEFAULT_ABI, u32(len(params.values)), ffi_ret_type, raw_data(ffi_params)) == .FFI_OK {
            ffi_func_decl : FFIFuncDecl
            ffi_func_decl.cif = cif
            ffi_func_decl.func_ptr = func_addr
            ffi_func_decl.ret_type = ffi_ret_type
            ffi_func_decl.param_types = ffi_params[:]
            append(&intr.ffi_func_decls, ffi_func_decl)
            func_idx := len(intr.ffi_func_decls) - 1
            return makeValue_Number({i64(func_idx), 1}), true
        } else {
            reportError(intr, call.callable.loc, "failed preparing ffi call") or_return
        }
    } else {
        reportError(intr, call.callable.loc, dynlib.last_error()) or_return
    }

    return {}, true
}

checkType :: proc(intr: ^Interpreter, loc: core.Location, value: core.Value, $T: typeid, msg: string) -> (val: T, ok: bool) {
    inner_type, is_match := value.(T)
    if is_match {
        return inner_type, true
    } else {
        reportError(intr, loc, "%s, but got '%s'", msg, formatType(value)) or_return
        return {}, false
    }
}

printScopes :: proc(intr: ^Interpreter) {
    fmt.println("BEGIN")
    for scope := intr.exe_ctx.curr_scope; scope != nil; scope = scope.parent {
        // fmt.println("  ", scope.ref_count)
        // for key, value in scope.vars {
        //     fmt.println("  ", key, scope.ref_count)
        // }
    }
    fmt.println("END")
}

@(require_results)
reportError :: proc(intr: ^Interpreter, loc: core.Location, f: string, args: ..any) -> bool {
    curr_file_ast := intr.files[intr.exe_ctx.curr_file_path].ast
    curr_file := curr_file_ast.src
    fmt.eprintfln("%s:", core.textColor("Stack trace", .Blue))

    for i := 0; i < len(intr.call_stack); i += 1 {
        call_expr_loc := intr.call_stack[i].expr.loc
        if loc == call_expr_loc do continue
        // core.printErr(call_expr_loc, str, ..args)
        fmt.eprintfln(
            "%s(\033[32m%s\033[0m:%d:%d):\n  -> %s",
            core.textColor("call", .Blue),
            call_expr_loc.file,
            call_expr_loc.line,
            call_expr_loc.col,
            curr_file[call_expr_loc.start:call_expr_loc.end]
        )
    }

    strs : [4]string = { "  -> ", curr_file[loc.start:loc.end], "\n",  f }
    str := strings.concatenate(strs[:], allocator=context.temp_allocator)

    core.printErr(loc, str, ..args)

    return false
}
