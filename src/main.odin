package ains

import "./core"
import "./parser"
import "core:os"
import "core:log"
import "./tokenizer"
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
    parser.parseFile(tokens)
}

readFile :: proc(path: string) -> ([]u8, bool) {
    content, ok := os.read_entire_file(path, allocator=context.temp_allocator)
    if !ok {
        core.printErr(nil, "failed to read file '%s'", path)
        return {}, false
    }
    return content, true
}
