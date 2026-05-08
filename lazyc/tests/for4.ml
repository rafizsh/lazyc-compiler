Long main() {
    Long count = 0;
    for (Long i = 0; i < 5; i = i + 1) {
        for (Long j = 0; j < 5; j = j + 1) {
            count = count + 1;
        }
    }
    return count;
}
