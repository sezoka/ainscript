package aincore

gcd :: proc(a: i32, b: i32) -> i32 {
    result: i32 = min(a, b)
    for result > 0 {
        if a % result == 0 && b % result == 0 {
            break
        }
        result -= 1
    }

    return result;
}
