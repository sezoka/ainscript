package libffi

import "core:c"

foreign import lib "system:ffi"


ffi_status :: enum c.int {
  FFI_OK = 0,
  FFI_BAD_TYPEDEF,
  FFI_BAD_ABI,
  FFI_BAD_ARGTYPE
}

ffi_cif :: struct {
    abi: ffi_abi,
    nargs: c.uint,
    arg_types: [^]^ffi_type,
    rtype: ^ffi_type,
    bytes: c.uint,
    flags: c.uint,
} 

ffi_abi :: enum c.int {
  FFI_FIRST_ABI = 1,
  FFI_UNIX64,
  FFI_WIN64,
  FFI_EFI64 = FFI_WIN64,
  FFI_GNUW64,
  FFI_LAST_ABI,
  FFI_DEFAULT_ABI = FFI_UNIX64
}

ffi_type :: struct {
    size: c.size_t,
    alignment: c.ushort,
    type: c.ushort,
    elements: [^]^ffi_type,
}


@(default_calling_convention="c", link_prefix="ffi_")
foreign lib {
    prep_cif :: proc(
        cif: ^ffi_cif,
        abi: ffi_abi,
        nargs: c.uint,
        rtype: ^ffi_type,
        atypes: [^]^ffi_type) -> ffi_status ---

    call :: proc(cif: ^ffi_cif,
        func: rawptr,
        rvalue: rawptr,
        avalue: [^]rawptr) ---
}

foreign lib {
    ffi_type_sint32: ffi_type
    ffi_type_pointer: ffi_type
    ffi_type_void: ffi_type
}
