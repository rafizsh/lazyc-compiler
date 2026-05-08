// 17: arrays as struct fields.
// Expected exit: 6
struct Vec { Long data[3]; Long len; }
Long main() {
    Vec v;
    v.len = 3;
    v.data[0] = 1;
    v.data[1] = 2;
    v.data[2] = 3;
    Long total = 0;
    Long i = 0;
    while (i < v.len) {
        total = total + v.data[i];
        i = i + 1;
    }
    return total;
}
