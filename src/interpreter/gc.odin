package aininterpreter

import "../core"
import "core:fmt"

runGC :: proc(intr: ^Interpreter) {
    free_all(context.temp_allocator)
    clear(&intr.marked_things)
    markFiles(intr)
    sweep(intr)
}

sweep :: proc(intr: ^Interpreter) {
    deleted_scopes := make([dynamic]^core.Scope, 0, len(intr.scopes), context.temp_allocator)
    deleted_values := make([dynamic]core.Value, 0, len(intr.heap_allocated_values), context.temp_allocator)
    deleted_funcs := make([dynamic]core.Value, 0, len(intr.functions), context.temp_allocator)

    for scope, _ in intr.scopes {
        if !isMarked(intr, scope) {
            append(&deleted_scopes, scope)
        }
    }
    for ptr, val in intr.heap_allocated_values {
        if !isMarked(intr, ptr) {
            append(&deleted_values, val)
        }
    }
    for func, _ in intr.functions {
        if !isMarked(intr, func) {
            append(&deleted_funcs, func)
        }
    }

    for scope in deleted_scopes {
        deleteScope(intr, scope)
    }
    for val in deleted_values {
        deleteValue(intr, val)
    }
    for func in deleted_funcs {
        deleteValue(intr, func)
    }
}

markFiles :: proc(intr: ^Interpreter) {
    for scope in intr.call_stack {
        markScope(intr, scope)
    }

    for _, file in intr.files {
        markScope(intr, file.exe_ctx.root_scope)
    }

    markScope(intr, intr.exe_ctx.curr_scope)
    markValue(intr, intr.exe_ctx.ret_value)
}

markScope :: proc(intr: ^Interpreter, scope: ^core.Scope) {
    if scope != nil && !isMarked(intr, scope) {
        markThing(intr, scope)
        for _, val in scope.vars {
            markValue(intr, val)
        }
        markScope(intr, scope.parent)
    }
}

markValue :: proc(intr: ^Interpreter, val: core.Value) {
    switch v in val {
    case core.Number:
    case core.Nil:
    case core.Bool:
    case core.String:
    case core.Module:
    case ^core.Func:
        markScope(intr, v.scope)
        markThing(intr, v)
    case ^core.Array:
        for item in v.values {
            markValue(intr, item)
        }
        markThing(intr, v)
    case ^core.Struct:
        for field in v.fields {
            markValue(intr, field.value)
        }
        markThing(intr, v)
    case rawptr:
    }
}

//
// markScopes :: proc(intr: ^Interpreter) {
//     for func, _ in intr.functions {
//         markScope(intr, func.scope)
//     }
//     for scope in intr.call_stack {
//         markScope(intr, scope)
//     }
//     markScope(intr, intr.curr_scope)
// }

markThing :: proc(intr: ^Interpreter, thing_ptr: rawptr) {
    intr.marked_things[thing_ptr] = {}
}

isMarked :: proc(intr: ^Interpreter, thing_ptr: rawptr) -> bool {
    return thing_ptr in intr.marked_things
}
//
// markScope :: proc(intr: ^Interpreter, scope: ^core.Scope) {
//     if scope != nil {
//         if isMarked(intr, scope) do return
//         markThing(intr, scope)
//         markScope(intr, scope.parent)
//     }
// }
