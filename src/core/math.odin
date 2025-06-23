package aincore

gcd :: proc(a: i64, b: i64) -> i64 {
    result: i64 = min(a, b)
    for result > 0 {
        if a % result == 0 && b % result == 0 {
            break
        }
        result -= 1
    }

    return result;
}
