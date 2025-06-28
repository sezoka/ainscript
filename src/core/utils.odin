package aincore

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
