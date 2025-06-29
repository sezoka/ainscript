package aincore

import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:os"

TextColor :: enum {
    Red,
    Blue,
    Yellow,
}

textColor :: proc($text: string, $color: TextColor) -> string {
    switch color {
    case .Red: return "\033[31m" + text + "\033[0m"
    case .Blue: return "\033[34m" + text + "\033[0m"
    case .Yellow: return "\033[33m" + text + "\033[0m"
    }
    return ""
}

relToAbsFilePath :: proc(root: string, relpath: string) -> (string, bool) {
    paths : [2]string = {root, filepath.dir(relpath)}
    path := filepath.join(paths[:], allocator=context.temp_allocator)
    abs, ok := filepath.abs(path, allocator=context.temp_allocator)
    if ok {
        path_and_name : [2]string = {abs, filepath.base(relpath)}
        return filepath.join(path_and_name[:]), ok
    } else {
        return path, ok
    }
}

readFile :: proc(path: string, loc: Maybe(Location) = nil) -> ([]u8, bool) {
    content, ok := os.read_entire_file(path, allocator=context.allocator)
    if !ok {
        printErr(loc, "failed to read file '%s'", path)
        return {}, false
    }
    return content, true
}
