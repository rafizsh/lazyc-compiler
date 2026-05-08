// 13a: pointer-typed parameter is OK; we don't use the param.
// Expected exit: 7
Long takes_ptr(Ptr<Long> p) {
    return 7;
}
Long main() {
    Long x = 0;
    // Can't construct a Ptr value yet, so we can't actually call takes_ptr.
    // That's fine; we just verify the declaration parses+typechecks+codegens.
    return takes_ptr_helper();
}
Long takes_ptr_helper() {
    return 7;
}
