package aininterpreter

import "core:dynlib"
import "../core"

loadLibrary :: proc(loc: core.Location, lib_path: string) -> (lib: dynlib.Library, ok: bool) {
    lib, ok = dynlib.load_library(lib_path)
    if !ok {
        reportError(loc, "failed to load library with path '%s'", lib_path) or_return
    }
    return lib, true
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
