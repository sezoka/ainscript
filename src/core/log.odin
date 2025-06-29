package aincore

import "core:fmt"
import "core:strings"

LogLevel :: enum {
    Error,
    Warn,
    Debug,
}

printMsg :: proc(level: LogLevel, loc: Maybe(Location), msg: string, args: ..any) {
    builder : strings.Builder
    strings.builder_init_none(&builder, allocator=context.temp_allocator)

    switch level {
    case .Error:
        strings.write_string(&builder, "\033[31mError\033[0m")
    case .Debug:
        strings.write_string(&builder, "\033[34mDebug\033[0m")
    case .Warn: 
        strings.write_string(&builder, "\033[33mWarn\033[0m")
    }

    loc, is_loc := loc.?
    if is_loc {
        strings.write_string(&builder, "(")
        strings.write_string(&builder, loc.file)
        strings.write_string(&builder, ":")
        strings.write_int(&builder, loc.line)
        strings.write_string(&builder, ":")
        strings.write_int(&builder, loc.col)
        strings.write_string(&builder, "):\n")
    } else {
        strings.write_string(&builder, ": ")
    }

    strings.write_string(&builder, msg)

    fmt.eprintfln(strings.to_string(builder), ..args)
}

printErr :: proc(loc: Maybe(Location), msg: string, args: ..any) {
    printMsg(.Error, loc, msg, ..args)
}

print :: proc(args: ..any) {
    fmt.println(..args)
}
