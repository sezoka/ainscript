package aininterpreter

import "core:dynlib"
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
    case "string":
        return &ffi.ffi_type_pointer, true
    case:
        reportError(loc, "unhandled type") or_return
        return {}, false
    }
}

FFIFuncDecl :: struct {
    cif: ffi.ffi_cif,
    func_ptr: rawptr,
    ret_type: ^ffi.ffi_type,
    param_types: []^ffi.ffi_type,
    as_param_types: []core.ValueType,
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
