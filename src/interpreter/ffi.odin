package aininterpreter

import "core:dynlib"
import "core:c"
import "core:fmt"
import "core:strings"
import "../core"
import "../ffi"

loadLibrary :: proc(loc: core.Location, lib_path: string) -> (lib: dynlib.Library, ok: bool) {
    lib, ok = dynlib.load_library(lib_path)
    if !ok {
        reportError(loc, "failed to load library with path '%s'", lib_path) or_return
    }
    return lib, true
}

ainsTypeStringToFFIType :: proc(type: string, loc: core.Location) -> (t: ^ffi.ffi_type, ok: bool) {
    switch type {
    case "void":
        return &ffi.ffi_type_void, true
    case "int":
        return &ffi.ffi_type_sint32, true
    case "pointer":
        return &ffi.ffi_type_pointer, true
    case "bool":
        return &ffi.ffi_type_sint32, true
    case "u8":
        return &ffi.ffi_type_uint8, true
    case:
        reportError(loc, "unhandled type") or_return
        return {}, false
    }
}

FFIFuncDecl :: struct {
    cif: ffi.ffi_cif,
    func_ptr: rawptr,
    ret_type: ^ffi.ffi_type,
    ret_type_str: string,
    param_types: []^ffi.ffi_type,
    param_types_strs: []string,
}

//
// callFunc :: proc(lib_path: string, func_name: string) {
//     if ok {
//         func_addr, found_func := dynlib.symbol_address(library, func_name)
//         if found_func {
//             fmt.printf("The symbol %q was found at the address %v", "a", func_addr)
//         } else {
//             fmt.eprintln(dynlib.last_error())
//         }
//     } else {
//         fmt.eprintln(dynlib.last_error())
//         return
//     }
// }

convertCValueToASValue :: proc(loc: core.Location, c_val: rawptr, type_str: string) -> (res: core.Value, ok: bool) {
    switch type_str {
    case "bool":
        val := (^bool)(c_val)^
        return makeValue_Bool(val), true
    case "int":
        val := (^c.int)(c_val)^
        return makeValue_Number({i64(val), 1}), true
    case "void":
        return makeValue_Nil(), true
    }
    reportError(loc, "can't convert C type '%s' to AinScript value", type_str) or_return
    return {}, false
}

convertASValueToCValuePtr :: proc(loc: core.Location, value: core.Value, target_type: string) -> (res: rawptr, ok: bool) {
    switch v in value {
    case core.Number:
        switch target_type {
        case "int":
            ptr := new(c.int, context.temp_allocator)
            ptr^ = c.int(v.numeral / v.denominator)
            return rawptr(ptr), true
        case "unt":
            ptr := new(c.uint, context.temp_allocator)
            val := v.numeral / v.denominator
            if 0 <= val {
                ptr^ = c.uint(val)
                return rawptr(ptr), true
            } else {
                reportError(loc, "can't convert negative number to c 'uint'") or_return
            }
        case "u8":
            ptr := new(u8, context.temp_allocator)
            val := v.numeral / v.denominator
            if 0 <= val {
                ptr^ = u8(val)
                return rawptr(ptr), true
            } else {
                reportError(loc, "can't convert negative number to c 'uint'") or_return
            }
        case:
            reportError(loc, "can't convert AinScript number to c '%s'", target_type) or_return
        }
    case core.Func:
        reportError(loc, "can't convert AinScript function to any c value") or_return
    case core.Nil:
        reportError(loc, "can't convert AinScript nil to any c value") or_return
    case core.Bool:
        switch target_type {
        case "int":
            ptr := new(c.int, context.temp_allocator)
            ptr^ = c.int(v)
            return rawptr(ptr), true
        case "unt":
            ptr := new(c.uint, context.temp_allocator)
            ptr^ = c.uint(v)
            return rawptr(ptr), true
        case:
            reportError(loc, "can't convert AinScript string to c '%s'", target_type) or_return
        }
    case core.String:
        switch target_type {
        case "pointer": 
            ptr := new(rawptr, context.temp_allocator)
            cstr := strings.clone_to_cstring(v, context.temp_allocator)
            ptr^ = rawptr(cstr)
            return rawptr(ptr), true
        case:
            reportError(loc, "can't convert AinScript bool to c '%s'", target_type) or_return
        }
    case core.Array:
    case core.Struct:
    case rawptr:
    }

    reportError(loc, "unhandled") or_return

    return {}, false
}
