package libffi

import "core:c"
import "core:log"

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


FFI_TYPE_VOID :: 0
FFI_TYPE_INT :: 1
FFI_TYPE_FLOAT :: 2
FFI_TYPE_DOUBLE :: 3
FFI_TYPE_LONGDOUBLE :: 4
FFI_TYPE_UINT8   :: 5
FFI_TYPE_SINT8   :: 6
FFI_TYPE_UINT16  :: 7
FFI_TYPE_SINT16  :: 8
FFI_TYPE_UINT32  :: 9
FFI_TYPE_SINT32  :: 10
FFI_TYPE_UINT64  :: 11
FFI_TYPE_SINT64  :: 12
FFI_TYPE_STRUCT  :: 13
FFI_TYPE_POINTER :: 14
FFI_TYPE_COMPLEX :: 15

getTypeName :: proc(type: c.ushort) -> string {
    switch type {
    case FFI_TYPE_VOID: return "void"
        case FFI_TYPE_INT: return "int"
    case FFI_TYPE_FLOAT: return "float"
    case FFI_TYPE_DOUBLE: return "double"
    case FFI_TYPE_LONGDOUBLE: return "long double"
    case FFI_TYPE_UINT8: return "uint8"
    case FFI_TYPE_SINT8: return "sint8"
    case FFI_TYPE_UINT16: return "uint16"
    case FFI_TYPE_SINT16: return "sint16"
    case FFI_TYPE_UINT32: return "uint32"
    case FFI_TYPE_SINT32: return "sint32"
    case FFI_TYPE_UINT64: return "uint64"
    case FFI_TYPE_SINT64: return "sint64"
    case FFI_TYPE_STRUCT: return "struct"
    case FFI_TYPE_POINTER: return "pointer"
    case FFI_TYPE_COMPLEX: return "complex"
    }
    log.error("unhandled ffi type")
    return ">>>unknown type<<<"
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
    ffi_type_uint8: ffi_type
    ffi_type_pointer: ffi_type
    ffi_type_void: ffi_type
}
