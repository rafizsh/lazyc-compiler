// text-stats: a non-trivial mylang program exercising the major features
// of the language. It writes a text file, reads it back, splits it into
// lines (linked-list of struct nodes built on the heap), computes stats
// over the lines, and prints a summary.
//
// Features exercised:
//   - struct decls including Ptr<Self> for linked lists
//   - heap allocation (alloc/free) and explicit reinterpreting casts
//   - file I/O (writef + readf round-trip)
//   - byte-level pointer arithmetic walking a buffer
//   - field access through pointers — (*cur).next, (*cur).text, etc.
//   - arrays (a Char buffer for line copies; Long histogram)
//   - all integer types via cast<>
//   - format-string print/println with %l, %s, %c, %i
//   - all control flow: if/else if/else, while, for, break, continue
//   - recursion
//   - functions with multiple parameters
//
// Expected behavior: writes /tmp/text-stats-input.txt, reads it back, and
// prints a report. Returns 0 on success, non-zero exit otherwise.

// ---------- Data ----------

struct Line {
    Ptr<Byte> text;       // heap-allocated null-terminated copy
    Long      length;     // bytes excluding null terminator
    Long      first_char; // ASCII code of first non-space char (0 if blank)
    Ptr<Line> next;
}

struct Stats {
    Long line_count;
    Long total_bytes;
    Long blank_lines;
    Long longest_line;
    Long histogram[26];   // counts of letters a..z (case-insensitive)
}

// ---------- String helpers (built from primitives) ----------

// Length of a null-terminated byte buffer, walking pointer-by-pointer.
Long strlen_b(Ptr<Byte> s) {
    Long n = 0;
    Ptr<Byte> p = s;
    while (*p != cast<Byte>(0)) {
        n = n + 1;
        p = p + 1;
    }
    return n;
}

// Copy [src .. src+n) bytes into a freshly heap-allocated, null-terminated
// buffer. Returns the new buffer (caller must free).
Ptr<Byte> dup_range(Ptr<Byte> src, Long n) {
    Ptr<Byte> buf = alloc(n + 1);
    if (buf == null) { exit(1); }
    Long i = 0;
    while (i < n) {
        buf[i] = src[i];
        i = i + 1;
    }
    buf[n] = cast<Byte>(0);
    return buf;
}

// Recursive integer-power demo (exercises recursion + multiple params).
Long ipow(Long base, Long exp) {
    if (exp == 0) { return 1; }
    if (exp == 1) { return base; }
    return base * ipow(base, exp - 1);
}

// Lowercase a single Char-coded byte. Non-letters are returned unchanged.
Byte to_lower(Byte b) {
    Long c = cast<Long>(b);
    if (c >= 65) {
        if (c <= 90) {
            return cast<Byte>(c + 32);
        }
    }
    return b;
}

// True if b is one of '\t', ' '.
Boolean is_blank_byte(Byte b) {
    Long c = cast<Long>(b);
    if (c == 32) { return true; }
    if (c == 9)  { return true; }
    return false;
}

// ---------- Building the linked list ----------

// Allocate a fresh Line node, zeroed. Caller chains it.
Ptr<Line> make_line() {
    Ptr<Byte> raw = alloc(40);   // sizeof(Line) is 32 (4 ptrs/longs)
    Ptr<Line> n = cast<Ptr<Line>>(raw);
    (*n).text = null;
    (*n).length = 0;
    (*n).first_char = 0;
    (*n).next = null;
    return n;
}

// Read text starting at p (null-terminated), build a linked list of Lines
// split on '\n'. Returns the head pointer. Empty input -> null head.
Ptr<Line> split_lines(Ptr<Byte> text) {
    Ptr<Line> head = null;
    Ptr<Line> tail = null;

    Ptr<Byte> p = text;
    Ptr<Byte> line_start = p;

    // Walk byte-by-byte. On '\n' or end-of-string, slice [line_start..p).
    while (true) {
        Byte b = *p;
        Long c = cast<Long>(b);
        Boolean at_end = (c == 0);
        Boolean at_nl  = (c == 10);
        Boolean stop = false;
        if (at_end) { stop = true; }
        if (at_nl)  { stop = true; }
        if (stop) {
            Long n = p - line_start;
            Ptr<Line> node = make_line();
            (*node).text   = dup_range(line_start, n);
            (*node).length = n;

            // Find first non-blank byte for first_char.
            Long fc = 0;
            for (Long i = 0; i < n; i = i + 1) {
                Byte bb = line_start[i];
                if (!is_blank_byte(bb)) {
                    fc = cast<Long>(bb);
                    break;
                }
            }
            (*node).first_char = fc;

            if (head == null) {
                head = node;
                tail = node;
            } else {
                (*tail).next = node;
                tail = node;
            }

            if (at_end) { break; }
            p = p + 1;
            line_start = p;
            continue;
        }
        p = p + 1;
    }
    return head;
}

// Free a list of Lines and their text buffers.
Long free_list(Ptr<Line> head) {
    Ptr<Line> cur = head;
    while (cur != null) {
        Ptr<Line> nxt = (*cur).next;
        if ((*cur).text != null) {
            free((*cur).text);
        }
        free(cast<Ptr<Byte>>(cur));
        cur = nxt;
    }
    return 0;
}

// ---------- Computing stats ----------

Long compute_stats(Ptr<Line> head, Ptr<Stats> out) {
    (*out).line_count = 0;
    (*out).total_bytes = 0;
    (*out).blank_lines = 0;
    (*out).longest_line = 0;
    for (Long i = 0; i < 26; i = i + 1) {
        (*out).histogram[i] = 0;
    }

    Ptr<Line> cur = head;
    while (cur != null) {
        (*out).line_count  = (*out).line_count + 1;
        (*out).total_bytes = (*out).total_bytes + (*cur).length;
        if ((*cur).first_char == 0) {
            (*out).blank_lines = (*out).blank_lines + 1;
        }
        if ((*cur).length > (*out).longest_line) {
            (*out).longest_line = (*cur).length;
        }

        // Histogram pass: walk the line's text byte by byte.
        Ptr<Byte> tp = (*cur).text;
        if (tp != null) {
            while (*tp != cast<Byte>(0)) {
                Byte lower = to_lower(*tp);
                Long lc = cast<Long>(lower);
                if (lc >= 97) {
                    if (lc <= 122) {
                        Long idx = lc - 97;
                        (*out).histogram[idx] = (*out).histogram[idx] + 1;
                    }
                }
                tp = tp + 1;
            }
        }
        cur = (*cur).next;
    }
    return 0;
}

// ---------- Reporting ----------

Long print_lines(Ptr<Line> head) {
    Long n = 1;
    Ptr<Line> cur = head;
    while (cur != null) {
        // Show line number, length, and first char (0 prints as 0).
        println("  line %l (len=%l, first=%l): %s",
                n, (*cur).length, (*cur).first_char,
                cast<String>((*cur).text));
        n = n + 1;
        cur = (*cur).next;
    }
    return 0;
}

Long print_stats(Ptr<Stats> s) {
    println("--- stats ---");
    println("  lines:        %l", (*s).line_count);
    println("  total bytes:  %l", (*s).total_bytes);
    println("  blank lines:  %l", (*s).blank_lines);
    println("  longest line: %l bytes", (*s).longest_line);

    // Print histogram letters that appear at least once.
    println("  letter counts (a..z, only nonzero):");
    Long total_letters = 0;
    for (Long i = 0; i < 26; i = i + 1) {
        Long count = (*s).histogram[i];
        total_letters = total_letters + count;
        if (count > 0) {
            Char c = cast<Char>(97 + i);
            println("    %c = %l", c, count);
        }
    }
    println("  total letters: %l", total_letters);
    return 0;
}

// ---------- Recursion sanity ----------

Long fib(Long n) {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}

// ---------- Main ----------

Long main() {
    // 1. Build a sample document and write it to disk.
    String doc = "The quick brown fox\njumps over the lazy dog.\n\nMylang is now self-hosting-ready.\n  indented line here\nLast line, no trailing newline";

    Boolean ok = writef("/tmp/text-stats-input.txt", cast<Ptr<Byte>>(doc));
    if (!ok) {
        println("error: could not write input file");
        return 1;
    }

    // 2. Read it back from disk.
    Ptr<Byte> contents = readf("/tmp/text-stats-input.txt");
    if (contents == null) {
        println("error: could not read back input file");
        return 2;
    }

    Long total = strlen_b(contents);
    println("=== read %l bytes from disk ===", total);
    println("");

    // 3. Split into a linked list of Lines.
    Ptr<Line> head = split_lines(contents);

    // 4. Print each line.
    println("=== lines ===");
    print_lines(head);
    println("");

    // 5. Compute and print stats.
    Stats s;
    compute_stats(head, &s);
    print_stats(&s);
    println("");

    // 6. Recursion + arithmetic checks (sanity).
    println("=== sanity ===");
    println("  fib(10)    = %l   (expected 55)",   fib(10));
    println("  fib(15)    = %l   (expected 610)",  fib(15));
    println("  ipow(2,10) = %l   (expected 1024)", ipow(2, 10));
    println("  ipow(3, 5) = %l   (expected 243)",  ipow(3, 5));

    // 7. Control-flow exercise: count even numbers in [0, 20) using continue,
    // bail out early with break.
    Long even_total = 0;
    Long bailed_at = -1;
    for (Long i = 0; i < 20; i = i + 1) {
        if (i % 2 == 1) { continue; }
        if (i == 14) { bailed_at = i; break; }
        even_total = even_total + i;
    }
    println("  even-sum 0..14 step 2 (skip odds, break at 14) = %l (expected 0+2+4+6+8+10+12 = 42)", even_total);
    println("  bailed at = %l", bailed_at);

    // 8. Sized integer round-trip via cast.
    Long big = 1000;
    Whole truncated  = cast<Whole>(big);
    Long  back       = cast<Long>(truncated);
    Byte  small      = cast<Byte>(big);     // wraps to 232
    Long  small_back = cast<Long>(small);
    println("  cast Long->Whole->Long round-trip: %l -> %l (expected 1000 -> 1000)", big, back);
    println("  cast Long->Byte->Long: %l -> %l (expected 1000 -> 232)", big, small_back);

    // 9. Cleanup.
    free_list(head);
    free(contents);

    println("");
    println("OK");
    return 0;
}
