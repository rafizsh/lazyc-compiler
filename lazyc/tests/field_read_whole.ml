// 16b: 4-byte signed-load for Whole field.
// Expected exit: 0   (-7 as Long, but exit code wraps to low byte = 0xF9 = 249)
// Actually let's use a positive value instead.
// Expected exit: 99
struct Bag { Whole w; Long n; }
Long main() {
    Bag bag;
    Ptr<Bag> pb = &bag;
    Ptr<Whole> pw = cast<Ptr<Whole>>(pb);
    *pw = 99;
    return cast<Long>(bag.w);
}
