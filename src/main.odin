package ains

import "./core"
import "./parser"
import "core:os"
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

    src, ok := readFile(path)
    if !ok do return

    tokens, tokenize_ok := tokenizer.tokenize(string(src))
    if !tokenize_ok do return

    // tokenizer.printTokens(tokens)
    file_ast, parse_ok := parser.parseFile(tokens)
    if !parse_ok do return

    interpreter.interpretFile(file_ast)

    // fmt.println(file_ast)
}

readFile :: proc(path: string) -> ([]u8, bool) {
    content, ok := os.read_entire_file(path, allocator=context.allocator)
    if !ok {
        core.printErr(nil, "failed to read file '%s'", path)
        return {}, false
    }
    return content, true
}
