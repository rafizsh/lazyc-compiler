Long double_it(Long x) { return x + x; }
Long triple_it(Long x) { return x + x + x; }
Long main() { return double_it(triple_it(4)); }
