package aininterpreter

import "core:dynlib"
import "core:c"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:log"
import "../core"
import "../ffi"

loadLibrary :: proc(loc: core.Location, lib_path: string) -> (lib: dynlib.Library, ok: bool) {
    lib, ok = dynlib.load_library(lib_path)
    if !ok {
        reportError(loc, "failed to load library with path '%s'", lib_path) or_return
    }
    return lib, true
}

ainsStructTypeToFFIStructType :: proc(s: ^core.Struct, loc: core.Location) -> (t: ^ffi.ffi_type, ok: bool) {
    struct_type := new(ffi.ffi_type)
    struct_type.type = ffi.FFI_TYPE_STRUCT
    elems := make([]^ffi.ffi_type, len(s.fields) + 1)
    struct_type.elements = raw_data(elems)
    for field, i in s.fields {
        elems[i] = ainsTypeStringToFFIType(field.value.(core.String), loc) or_return // FIXME: 
    }
    return struct_type, true
}

ainsTypeStringToFFIType :: proc(type: string, loc: core.Location) -> (t: ^ffi.ffi_type, ok: bool) {
    switch type {
    case "void":
        return &ffi.ffi_type_void, true
    case "i32":
        return &ffi.ffi_type_sint32, true
    case "pointer":
        return &ffi.ffi_type_pointer, true
    case "u32":
        return &ffi.ffi_type_sint32, true
    case "u8":
        return &ffi.ffi_type_uint8, true
    case:
        reportError(loc, "unhandled type '%s'", type) or_return
        return {}, false
    }
}

FFIFuncDecl :: struct {
    cif: ffi.ffi_cif,
    func_ptr: rawptr,
    ret_type: ^ffi.ffi_type,
    param_types: []^ffi.ffi_type,
}

convertCValueToASValue :: proc(loc: core.Location, c_val: rawptr, target_type: ^ffi.ffi_type) -> (res: core.Value, ok: bool) {
    switch target_type.type {
    case ffi.FFI_TYPE_UINT8:
        val := (^u8)(c_val)^
        return makeValue_Number({i64(val), 1}), true
    case ffi.FFI_TYPE_SINT32:
        val := (^i32)(c_val)^
        return makeValue_Number({i64(val), 1}), true
    case ffi.FFI_TYPE_VOID:
        return makeValue_Nil(), true
    }
    reportError(loc, "can't convert C type '%s' to AinScript value", ffi.getTypeName(target_type.type)) or_return
    return {}, false
}

convertASValueToCValuePtr :: proc(
    loc: core.Location,
    value: core.Value,
    ffi_target_type: ^ffi.ffi_type
) -> (res: rawptr, ok: bool) {
    switch v in value {
    case core.Number:
        switch ffi_target_type.type {
        case ffi.FFI_TYPE_SINT32:
            ptr := new(i32, context.temp_allocator)
            ptr^ = c.int(v.numeral / v.denominator)
            return rawptr(ptr), true
        case ffi.FFI_TYPE_UINT32:
            ptr := new(u32, context.temp_allocator)
            val := v.numeral / v.denominator
            if 0 <= val {
                ptr^ = c.uint(val)
                return rawptr(ptr), true
            } else {
                reportError(loc, "can't convert negative number to 'u32'") or_return
            }
        case ffi.FFI_TYPE_UINT8:
            ptr := new(u8, context.temp_allocator)
            val := v.numeral / v.denominator
            if 0 <= val {
                ptr^ = u8(val)
                return rawptr(ptr), true
            } else {
                reportError(loc, "can't convert negative number to 'u8'") or_return
            }
        case:
            reportError(loc, "can't convert AinScript number to '%s'", ffi.getTypeName(ffi_target_type.type)) or_return
        }
    case core.Func:
        reportError(loc, "can't convert AinScript function to any c value") or_return
    case core.Nil:
        reportError(loc, "can't convert AinScript nil to any c value") or_return
    case core.Bool:
        switch ffi_target_type.type {
        case ffi.FFI_TYPE_SINT32:
            ptr := new(i32, context.temp_allocator)
            ptr^ = c.int(v)
            return rawptr(ptr), true
        case ffi.FFI_TYPE_UINT32:
            ptr := new(u32, context.temp_allocator)
            ptr^ = c.uint(v)
            return rawptr(ptr), true
        case:
            reportError(loc, "can't convert AinScript string to '%s'", ffi.getTypeName(ffi_target_type.type)) or_return
        }
    case core.String:
        switch ffi_target_type.type {
        case ffi.FFI_TYPE_POINTER: 
            ptr := new(rawptr, context.temp_allocator)
            cstr := strings.clone_to_cstring(v, context.temp_allocator)
            ptr^ = rawptr(cstr)
            return rawptr(ptr), true
        case:
            reportError(loc, "can't convert AinScript bool to c '%s'", ffi.getTypeName(ffi_target_type.type)) or_return
        }
    case ^core.Array:
    case ^core.Struct:
        len := 0
        for ffi_target_type.elements[len] != nil do len += 1
        start_ptr := raw_data(make([]u8, ffi_target_type.size, context.temp_allocator))
        curr_elem_ptr := start_ptr
        for field, i in v.fields {
            ffi_type := ffi_target_type.elements[i]
            converted_field := convertASValueToCValuePtr(loc, field.value, ffi_type) or_return
            mem.copy(curr_elem_ptr, converted_field, int(ffi_type.size))
            curr_elem_ptr = mem.ptr_offset(curr_elem_ptr, ffi_type.size)
            if !mem.is_aligned(curr_elem_ptr, int(ffi_target_type.alignment)) {
                converted_field = mem.align_forward(curr_elem_ptr, uintptr(ffi_target_type.alignment))
            }
        }
        return start_ptr, true
    case rawptr:
    }

    log.info("unhandled")

    return {}, false
}
