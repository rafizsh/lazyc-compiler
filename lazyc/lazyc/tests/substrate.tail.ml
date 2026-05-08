// 21a: substrate smoke test.
//
// Compiled by concatenating lib/strs.ml + lib/buf.ml + lib/ptrvec.ml + this file.
// Tests every helper function with assertions. On success: prints "OK",
// returns 0. On any failure: prints which test failed, returns nonzero.

// ---- Test infrastructure ----

Long check(Boolean cond, Ptr<Byte> name, Ptr<Long> failures, Ptr<Long> total) {
    *total = *total + 1;
    if (!cond) {
        println("  FAIL: %s", cast<String>(name));
        *failures = *failures + 1;
    }
    return 0;
}

Long check_eq_long(Long got, Long want, Ptr<Byte> name, Ptr<Long> failures, Ptr<Long> total) {
    *total = *total + 1;
    if (got != want) {
        println("  FAIL: %s  got=%l want=%l", cast<String>(name), got, want);
        *failures = *failures + 1;
    }
    return 0;
}

Long check_streq(Ptr<Byte> got, Ptr<Byte> want, Ptr<Byte> name, Ptr<Long> failures, Ptr<Long> total) {
    *total = *total + 1;
    if (!ml_streq(got, want)) {
        println("  FAIL: %s", cast<String>(name));
        println("    got:  '%s'", cast<String>(got));
        println("    want: '%s'", cast<String>(want));
        *failures = *failures + 1;
    }
    return 0;
}

// ---- String helpers ----

Long test_strlen(Ptr<Long> failures, Ptr<Long> total) {
    println("strlen tests:");
    check_eq_long(ml_strlen(cast<Ptr<Byte>>("")), 0, cast<Ptr<Byte>>("strlen empty"), failures, total);
    check_eq_long(ml_strlen(cast<Ptr<Byte>>("a")), 1, cast<Ptr<Byte>>("strlen a"), failures, total);
    check_eq_long(ml_strlen(cast<Ptr<Byte>>("hello, world!")), 13, cast<Ptr<Byte>>("strlen hello"), failures, total);
    check_eq_long(ml_strlen(null), 0, cast<Ptr<Byte>>("strlen null"), failures, total);
    return 0;
}

Long test_streq(Ptr<Long> failures, Ptr<Long> total) {
    println("streq tests:");
    check(ml_streq(cast<Ptr<Byte>>("hello"), cast<Ptr<Byte>>("hello")), cast<Ptr<Byte>>("streq same"), failures, total);
    check(!ml_streq(cast<Ptr<Byte>>("hello"), cast<Ptr<Byte>>("world")), cast<Ptr<Byte>>("streq diff"), failures, total);
    check(!ml_streq(cast<Ptr<Byte>>("a"), cast<Ptr<Byte>>("ab")), cast<Ptr<Byte>>("streq prefix"), failures, total);
    check(!ml_streq(cast<Ptr<Byte>>("ab"), cast<Ptr<Byte>>("a")), cast<Ptr<Byte>>("streq longer"), failures, total);
    check(ml_streq(cast<Ptr<Byte>>(""), cast<Ptr<Byte>>("")), cast<Ptr<Byte>>("streq empty"), failures, total);
    check(ml_streq(null, null), cast<Ptr<Byte>>("streq null null"), failures, total);
    check(!ml_streq(null, cast<Ptr<Byte>>("x")), cast<Ptr<Byte>>("streq null x"), failures, total);
    return 0;
}

Long test_strcmp(Ptr<Long> failures, Ptr<Long> total) {
    println("strcmp tests:");
    check_eq_long(ml_strcmp(cast<Ptr<Byte>>("aaa"), cast<Ptr<Byte>>("aaa")), 0, cast<Ptr<Byte>>("strcmp eq"), failures, total);
    check_eq_long(ml_strcmp(cast<Ptr<Byte>>("aaa"), cast<Ptr<Byte>>("aab")), -1, cast<Ptr<Byte>>("strcmp lt"), failures, total);
    check_eq_long(ml_strcmp(cast<Ptr<Byte>>("aab"), cast<Ptr<Byte>>("aaa")), 1, cast<Ptr<Byte>>("strcmp gt"), failures, total);
    check_eq_long(ml_strcmp(cast<Ptr<Byte>>("aa"), cast<Ptr<Byte>>("aaa")), -1, cast<Ptr<Byte>>("strcmp prefix lt"), failures, total);
    return 0;
}

Long test_memcpy_dup(Ptr<Long> failures, Ptr<Long> total) {
    println("memcpy/memdup tests:");
    Ptr<Byte> src = cast<Ptr<Byte>>("hello world");
    Ptr<Byte> copy = ml_memdup(src, 5);
    check_streq(copy, cast<Ptr<Byte>>("hello"), cast<Ptr<Byte>>("memdup first 5"), failures, total);
    free(copy);

    Ptr<Byte> copy2 = ml_strdup(cast<Ptr<Byte>>("dupme"));
    check_streq(copy2, cast<Ptr<Byte>>("dupme"), cast<Ptr<Byte>>("strdup"), failures, total);
    // Verify it's an independent allocation:
    copy2[0] = cast<Byte>(88);    // 'X'
    check_streq(copy2, cast<Ptr<Byte>>("Xupme"), cast<Ptr<Byte>>("strdup mutated"), failures, total);
    free(copy2);
    return 0;
}

Long test_predicates(Ptr<Long> failures, Ptr<Long> total) {
    println("predicate tests:");
    check(ml_is_digit(cast<Byte>(48)),   cast<Ptr<Byte>>("is_digit '0'"), failures, total);
    check(ml_is_digit(cast<Byte>(57)),   cast<Ptr<Byte>>("is_digit '9'"), failures, total);
    check(!ml_is_digit(cast<Byte>(47)),  cast<Ptr<Byte>>("is_digit '/'"), failures, total);
    check(!ml_is_digit(cast<Byte>(58)),  cast<Ptr<Byte>>("is_digit ':'"), failures, total);

    check(ml_is_ident_start(cast<Byte>(65)),  cast<Ptr<Byte>>("is_ident_start 'A'"), failures, total);
    check(ml_is_ident_start(cast<Byte>(122)), cast<Ptr<Byte>>("is_ident_start 'z'"), failures, total);
    check(ml_is_ident_start(cast<Byte>(95)),  cast<Ptr<Byte>>("is_ident_start '_'"), failures, total);
    check(!ml_is_ident_start(cast<Byte>(48)), cast<Ptr<Byte>>("is_ident_start '0'"), failures, total);

    check(ml_is_ident_cont(cast<Byte>(48)),   cast<Ptr<Byte>>("is_ident_cont '0'"), failures, total);
    check(ml_is_ident_cont(cast<Byte>(95)),   cast<Ptr<Byte>>("is_ident_cont '_'"), failures, total);

    check(ml_is_space(cast<Byte>(32)),    cast<Ptr<Byte>>("is_space ' '"), failures, total);
    check(ml_is_space(cast<Byte>(9)),     cast<Ptr<Byte>>("is_space tab"), failures, total);
    check(ml_is_space(cast<Byte>(10)),    cast<Ptr<Byte>>("is_space '\\n'"), failures, total);
    check(!ml_is_space(cast<Byte>(65)),   cast<Ptr<Byte>>("is_space 'A'"), failures, total);
    return 0;
}

Long test_atol(Ptr<Long> failures, Ptr<Long> total) {
    println("atol tests:");
    check_eq_long(ml_atol(cast<Ptr<Byte>>("0")),       0,      cast<Ptr<Byte>>("atol 0"), failures, total);
    check_eq_long(ml_atol(cast<Ptr<Byte>>("42")),      42,     cast<Ptr<Byte>>("atol 42"), failures, total);
    check_eq_long(ml_atol(cast<Ptr<Byte>>("12345")),   12345,  cast<Ptr<Byte>>("atol 12345"), failures, total);
    check_eq_long(ml_atol(cast<Ptr<Byte>>("-1")),      -1,     cast<Ptr<Byte>>("atol -1"), failures, total);
    check_eq_long(ml_atol(cast<Ptr<Byte>>("-99999")),  -99999, cast<Ptr<Byte>>("atol -99999"), failures, total);
    check_eq_long(ml_atol(cast<Ptr<Byte>>("xyz")),     0,      cast<Ptr<Byte>>("atol non-digit"), failures, total);
    check_eq_long(ml_atol(cast<Ptr<Byte>>("10abc")),   10,     cast<Ptr<Byte>>("atol stops"), failures, total);
    return 0;
}

// ---- Buf tests ----

Long test_buf_basic(Ptr<Long> failures, Ptr<Long> total) {
    println("buf basic tests:");
    Buf b;
    buf_init(&b);
    check_eq_long(b.len, 0, cast<Ptr<Byte>>("buf init len"), failures, total);
    check(b.cap > 0, cast<Ptr<Byte>>("buf init cap > 0"), failures, total);

    buf_push_byte(&b, cast<Byte>(72));   // 'H'
    buf_push_byte(&b, cast<Byte>(105));  // 'i'
    check_eq_long(b.len, 2, cast<Ptr<Byte>>("buf len after 2 bytes"), failures, total);
    check_streq(b.data, cast<Ptr<Byte>>("Hi"), cast<Ptr<Byte>>("buf content Hi"), failures, total);

    buf_push_str(&b, cast<Ptr<Byte>>(", world!"));
    check_streq(b.data, cast<Ptr<Byte>>("Hi, world!"), cast<Ptr<Byte>>("buf after push_str"), failures, total);
    check_eq_long(b.len, 10, cast<Ptr<Byte>>("buf len Hi, world!"), failures, total);

    buf_free(&b);
    return 0;
}

Long test_buf_grow(Ptr<Long> failures, Ptr<Long> total) {
    println("buf grow tests:");
    Buf b;
    buf_init(&b);
    Long initial_cap = b.cap;
    // Force several growths.
    Long i = 0;
    while (i < 1000) {
        buf_push_byte(&b, cast<Byte>(65 + (i % 26)));   // A..Z repeating
        i = i + 1;
    }
    check_eq_long(b.len, 1000, cast<Ptr<Byte>>("buf len after 1000"), failures, total);
    check(b.cap > initial_cap, cast<Ptr<Byte>>("buf grew"), failures, total);
    // First three chars should be 'A', 'B', 'C'.
    check_eq_long(cast<Long>(b.data[0]), 65, cast<Ptr<Byte>>("buf[0] = A"), failures, total);
    check_eq_long(cast<Long>(b.data[1]), 66, cast<Ptr<Byte>>("buf[1] = B"), failures, total);
    check_eq_long(cast<Long>(b.data[2]), 67, cast<Ptr<Byte>>("buf[2] = C"), failures, total);
    // Index 25 is 'Z', 26 is back to 'A'.
    check_eq_long(cast<Long>(b.data[25]), 90, cast<Ptr<Byte>>("buf[25] = Z"), failures, total);
    check_eq_long(cast<Long>(b.data[26]), 65, cast<Ptr<Byte>>("buf[26] = A"), failures, total);
    // Null-terminator at len.
    check_eq_long(cast<Long>(b.data[b.len]), 0, cast<Ptr<Byte>>("buf null-terminated"), failures, total);
    buf_free(&b);
    return 0;
}

Long test_buf_long(Ptr<Long> failures, Ptr<Long> total) {
    println("buf long tests:");
    Buf b;
    buf_init(&b);
    buf_push_long(&b, 0);
    buf_push_byte(&b, cast<Byte>(32));   // ' '
    buf_push_long(&b, 42);
    buf_push_byte(&b, cast<Byte>(32));
    buf_push_long(&b, -7);
    buf_push_byte(&b, cast<Byte>(32));
    buf_push_long(&b, 1234567890);
    check_streq(b.data, cast<Ptr<Byte>>("0 42 -7 1234567890"),
                cast<Ptr<Byte>>("buf push_long"), failures, total);
    buf_free(&b);
    return 0;
}

// ---- PtrVec tests ----

Long test_ptrvec_basic(Ptr<Long> failures, Ptr<Long> total) {
    println("ptrvec basic tests:");
    PtrVec v;
    ptrvec_init(&v);
    check_eq_long(v.count, 0, cast<Ptr<Byte>>("ptrvec init count"), failures, total);
    check(v.cap > 0, cast<Ptr<Byte>>("ptrvec init cap > 0"), failures, total);

    ptrvec_push(&v, cast<Ptr<Byte>>("alpha"));
    ptrvec_push(&v, cast<Ptr<Byte>>("beta"));
    ptrvec_push(&v, cast<Ptr<Byte>>("gamma"));
    check_eq_long(v.count, 3, cast<Ptr<Byte>>("ptrvec count after 3"), failures, total);

    Ptr<Byte> g0 = ptrvec_get(&v, 0);
    Ptr<Byte> g1 = ptrvec_get(&v, 1);
    Ptr<Byte> g2 = ptrvec_get(&v, 2);
    check_streq(g0, cast<Ptr<Byte>>("alpha"), cast<Ptr<Byte>>("ptrvec get 0"), failures, total);
    check_streq(g1, cast<Ptr<Byte>>("beta"),  cast<Ptr<Byte>>("ptrvec get 1"), failures, total);
    check_streq(g2, cast<Ptr<Byte>>("gamma"), cast<Ptr<Byte>>("ptrvec get 2"), failures, total);

    ptrvec_set(&v, 1, cast<Ptr<Byte>>("BETA"));
    check_streq(ptrvec_get(&v, 1), cast<Ptr<Byte>>("BETA"), cast<Ptr<Byte>>("ptrvec set"), failures, total);

    ptrvec_free(&v);
    return 0;
}

Long test_ptrvec_grow(Ptr<Long> failures, Ptr<Long> total) {
    println("ptrvec grow tests:");
    PtrVec v;
    ptrvec_init(&v);
    Long initial_cap = v.cap;
    // Add many items, forcing growth.
    Long i = 0;
    while (i < 100) {
        // Use a fixed string for simplicity; we only need different *pointers*
        // for some tests, but here we just push the same pointer many times.
        ptrvec_push(&v, cast<Ptr<Byte>>("item"));
        i = i + 1;
    }
    check_eq_long(v.count, 100, cast<Ptr<Byte>>("ptrvec count 100"), failures, total);
    check(v.cap > initial_cap, cast<Ptr<Byte>>("ptrvec grew"), failures, total);
    // Random spot-checks.
    check_streq(ptrvec_get(&v, 0),  cast<Ptr<Byte>>("item"), cast<Ptr<Byte>>("ptrvec[0]"), failures, total);
    check_streq(ptrvec_get(&v, 50), cast<Ptr<Byte>>("item"), cast<Ptr<Byte>>("ptrvec[50]"), failures, total);
    check_streq(ptrvec_get(&v, 99), cast<Ptr<Byte>>("item"), cast<Ptr<Byte>>("ptrvec[99]"), failures, total);
    ptrvec_free(&v);
    return 0;
}

// ---- Main ----

Long main() {
    println("=== lazyc substrate smoke test ===");
    Long failures = 0;
    Long total = 0;
    test_strlen(&failures, &total);
    test_streq(&failures, &total);
    test_strcmp(&failures, &total);
    test_memcpy_dup(&failures, &total);
    test_predicates(&failures, &total);
    test_atol(&failures, &total);
    test_buf_basic(&failures, &total);
    test_buf_grow(&failures, &total);
    test_buf_long(&failures, &total);
    test_ptrvec_basic(&failures, &total);
    test_ptrvec_grow(&failures, &total);

    println("");
    println("ran %l checks", total);
    if (failures == 0) {
        println("ALL TESTS PASS");
        return 0;
    }
    println("%l TESTS FAILED", failures);
    return 1;
}
