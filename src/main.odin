package ains

import "./core"
import "./parser"
import "core:os"
import "core:os/os2"
import "core:fmt"
import "core:log"
import "./tokenizer"
import "./interpreter"
import vmem "core:mem/virtual"

main :: proc() {
    context.logger = log.create_console_logger()
    if len(os.args) != 2 {
        core.print("usage: ais <file.ains>")
        return
    }
    path := os.args[1]


    src, ok := core.readFile(path)
    if !ok do return

    abs_path, abs_ok := core.relToAbsFilePath(context.allocator, "./", path)
    assert(abs_ok)

    tokens, tokenize_ok := tokenizer.tokenize(string(src), abs_path)
    if !tokenize_ok do return

    file_ast, parse_ok := parser.parseFile(tokens, abs_path)
    if !parse_ok do return

    interpreter.interpretMainFile(file_ast)
}
