// bim — a small vim-like modal text editor written in lazyc.
//
// Modes:
//   NORMAL  — h/j/k/l move; i enters INSERT; : enters COMMAND;
//             x deletes char; dd deletes line; o opens line below;
//             0 / $ go to start/end of line; gg / G top/bottom.
//   INSERT  — typed chars are inserted; Esc returns to NORMAL.
//   COMMAND — text after ':' is buffered; Enter executes; Esc cancels.
//             Supported: :w :q :wq :q!
//
// Architecture: array of dynamic byte buffers, one per line. The screen
// is redrawn from scratch on every keystroke via a single batched write
// to stdout (so no flicker). Terminal is set to raw mode on startup
// and restored on exit. Arrow keys, Backspace, and Esc are decoded
// from raw byte sequences.

// ---- Extern syscall trampolines (defined in syscall.asm) ----
extern Long lazyc_sys_read(Long fd, Ptr<Byte> buf, Long n);
extern Long lazyc_sys_write(Long fd, Ptr<Byte> buf, Long n);
extern Long lazyc_sys_ioctl(Long fd, Long request, Ptr<Byte> argp);
extern Long lazyc_sys_exit(Long code);


// ============================================================
// CONSTANTS
// ============================================================

// Termios ioctl request numbers (Linux x86-64).
Long TCGETS()      { return 21505; }    // 0x5401
Long TCSETS()      { return 21506; }    // 0x5402
Long TIOCGWINSZ()  { return 21523; }    // 0x5413

// Termios byte layout (Linux). Total struct size 60 bytes; we allocate 64.
//   offset 0   c_iflag (4 bytes)
//   offset 4   c_oflag (4 bytes)
//   offset 8   c_cflag (4 bytes)
//   offset 12  c_lflag (4 bytes)
//   offset 16  c_line  (1 byte)
//   offset 17  c_cc[NCCS]  (NCCS=19 on Linux)
//   offset 36  (padding)
//   offset 40  c_ispeed (4)
//   offset 44  c_ospeed (4)
Long TERMIOS_SIZE()  { return 64; }
Long TERMIOS_IFLAG() { return 0; }
Long TERMIOS_OFLAG() { return 4; }
Long TERMIOS_LFLAG() { return 12; }
Long TERMIOS_CC()    { return 17; }
Long VTIME_OFFSET()  { return 5; }
Long VMIN_OFFSET()   { return 6; }

// c_lflag bits
Long ICANON() { return 2; }
Long ECHO_FL(){ return 8; }
Long ISIG()   { return 1; }
Long IEXTEN() { return 32768; }

// c_iflag bits
Long IXON()   { return 1024; }
Long ICRNL()  { return 256; }
Long BRKINT() { return 2; }
Long INPCK()  { return 16; }
Long ISTRIP() { return 32; }

// c_oflag bits
Long OPOST()  { return 1; }

// Editor modes.
Long MODE_NORMAL()  { return 0; }
Long MODE_INSERT()  { return 1; }
Long MODE_COMMAND() { return 2; }

// Special key codes (returned by read_key in a single Long).
// Regular ASCII (0..127) is its own value. Special keys use
// values >= 256 to avoid collision.
Long KEY_NONE()      { return -1; }   // would block / no input
Long KEY_ESC()       { return 27; }
Long KEY_BACKSPACE() { return 127; }
Long KEY_ENTER()     { return 13; }
Long KEY_UP()        { return 1000; }
Long KEY_DOWN()      { return 1001; }
Long KEY_RIGHT()     { return 1002; }
Long KEY_LEFT()      { return 1003; }


// ============================================================
// LINE BUFFER (a dynamic byte array per line)
// ============================================================

struct Line {
    Ptr<Byte> data;     // bytes in this line (no trailing newline; not null-terminated)
    Long len;           // number of bytes used
    Long cap;           // capacity of data
}

Long line_init(Ptr<Line> ln) {
    (*ln).data = alloc(16);
    (*ln).len  = 0;
    (*ln).cap  = 16;
    return 0;
}

Long line_grow(Ptr<Line> ln, Long need) {
    if ((*ln).len + need <= (*ln).cap) { return 0; }
    Long new_cap = (*ln).cap * 2;
    while (new_cap < (*ln).len + need) { new_cap = new_cap * 2; }
    Ptr<Byte> nd = alloc(new_cap);
    Long i = 0;
    while (i < (*ln).len) {
        nd[i] = (*ln).data[i];
        i = i + 1;
    }
    free((*ln).data);
    (*ln).data = nd;
    (*ln).cap = new_cap;
    return 0;
}

Long line_push_byte(Ptr<Line> ln, Byte b) {
    line_grow(ln, 1);
    (*ln).data[(*ln).len] = b;
    (*ln).len = (*ln).len + 1;
    return 0;
}

// Insert byte at position pos, shifting later bytes right by 1.
Long line_insert(Ptr<Line> ln, Long pos, Byte b) {
    line_grow(ln, 1);
    Long i = (*ln).len;
    while (i > pos) {
        (*ln).data[i] = (*ln).data[i - 1];
        i = i - 1;
    }
    (*ln).data[pos] = b;
    (*ln).len = (*ln).len + 1;
    return 0;
}

// Delete byte at position pos, shifting later bytes left by 1.
Long line_delete(Ptr<Line> ln, Long pos) {
    if (pos < 0)            { return 0; }
    if (pos >= (*ln).len)   { return 0; }
    Long i = pos;
    while (i < (*ln).len - 1) {
        (*ln).data[i] = (*ln).data[i + 1];
        i = i + 1;
    }
    (*ln).len = (*ln).len - 1;
    return 0;
}

Long line_free(Ptr<Line> ln) {
    if ((*ln).data != null) {
        free((*ln).data);
        (*ln).data = cast<Ptr<Byte>>(null);
    }
    (*ln).len = 0;
    (*ln).cap = 0;
    return 0;
}


// ============================================================
// EDITOR STATE
// ============================================================

struct Editor {
    Ptr<Byte>  lines;       // really Ptr<Line>; each entry is a Line struct (24 bytes)
    Long       num_lines;
    Long       cap_lines;

    Long       cx;          // cursor column within current line (byte index)
    Long       cy;          // cursor row (line index)
    Long       row_off;     // top row currently displayed
    Long       col_off;     // leftmost column displayed

    Long       screen_rows; // total terminal rows
    Long       screen_cols; // total terminal cols

    Long       mode;
    Boolean    dirty;
    Boolean    quitting;

    Ptr<Byte>  filename;    // null-terminated; null if no file
    Long       filename_len;

    Ptr<Byte>  status_msg;  // null-terminated short status; allocated
    Long       status_len;

    Ptr<Line>  cmd_buf;     // command-mode input buffer (single Line)

    Ptr<Byte>  out_buf;     // batched output buffer
    Long       out_len;
    Long       out_cap;

    Ptr<Byte>  saved_termios;  // 64 bytes; restored on exit
    Long       pushback;       // -1 = empty, else 0..255 held byte
}

// Get a Ptr<Line> to entry i in the lines array.
Ptr<Line> ed_line(Ptr<Editor> ed, Long i) {
    Ptr<Byte> base = (*ed).lines;
    Long offset = i * 24;
    Ptr<Byte> p = base + offset;
    return cast<Ptr<Line>>(p);
}

Long ed_grow_lines(Ptr<Editor> ed, Long need) {
    if ((*ed).num_lines + need <= (*ed).cap_lines) { return 0; }
    Long nc = (*ed).cap_lines * 2;
    if (nc < 16) { nc = 16; }
    while (nc < (*ed).num_lines + need) { nc = nc * 2; }
    Ptr<Byte> nd = alloc(nc * 24);
    Long i = 0;
    while (i < (*ed).num_lines * 24) {
        nd[i] = (*ed).lines[i];
        i = i + 1;
    }
    if ((*ed).lines != null) { free((*ed).lines); }
    (*ed).lines = nd;
    (*ed).cap_lines = nc;
    return 0;
}

Long ed_append_empty_line(Ptr<Editor> ed) {
    ed_grow_lines(ed, 1);
    Ptr<Line> ln = ed_line(ed, (*ed).num_lines);
    line_init(ln);
    (*ed).num_lines = (*ed).num_lines + 1;
    return 0;
}

// Insert an empty line at position pos (lines[pos..] shift down by 1).
Long ed_insert_line_at(Ptr<Editor> ed, Long pos) {
    ed_grow_lines(ed, 1);
    Long i = (*ed).num_lines * 24;
    Long target = pos * 24;
    while (i > target) {
        (*ed).lines[i + 24 - 1] = (*ed).lines[i - 1];
        i = i - 1;
    }
    (*ed).num_lines = (*ed).num_lines + 1;
    Ptr<Line> nln = ed_line(ed, pos);
    line_init(nln);
    return 0;
}

// Delete line at pos.
Long ed_delete_line_at(Ptr<Editor> ed, Long pos) {
    if (pos < 0)               { return 0; }
    if (pos >= (*ed).num_lines){ return 0; }
    Ptr<Line> dead = ed_line(ed, pos);
    line_free(dead);
    Long src = (pos + 1) * 24;
    Long dst = pos * 24;
    Long end = (*ed).num_lines * 24;
    while (src < end) {
        (*ed).lines[dst] = (*ed).lines[src];
        src = src + 1;
        dst = dst + 1;
    }
    (*ed).num_lines = (*ed).num_lines - 1;
    return 0;
}


// ============================================================
// OUTPUT BUFFER (batched writes)
// ============================================================

Long out_grow(Ptr<Editor> ed, Long need) {
    if ((*ed).out_len + need <= (*ed).out_cap) { return 0; }
    Long nc = (*ed).out_cap * 2;
    if (nc < 256) { nc = 256; }
    while (nc < (*ed).out_len + need) { nc = nc * 2; }
    Ptr<Byte> nd = alloc(nc);
    Long i = 0;
    while (i < (*ed).out_len) {
        nd[i] = (*ed).out_buf[i];
        i = i + 1;
    }
    if ((*ed).out_buf != null) { free((*ed).out_buf); }
    (*ed).out_buf = nd;
    (*ed).out_cap = nc;
    return 0;
}

Long out_byte(Ptr<Editor> ed, Byte b) {
    out_grow(ed, 1);
    (*ed).out_buf[(*ed).out_len] = b;
    (*ed).out_len = (*ed).out_len + 1;
    return 0;
}

// Append null-terminated string s to the output buffer.
Long out_str(Ptr<Editor> ed, Ptr<Byte> s) {
    Long i = 0;
    while (true) {
        Long c = cast<Long>(s[i]);
        if (c == 0) { break; }
        out_byte(ed, cast<Byte>(c));
        i = i + 1;
    }
    return 0;
}

// Append n bytes from s to the output buffer (no null termination needed).
Long out_bytes(Ptr<Editor> ed, Ptr<Byte> s, Long n) {
    Long i = 0;
    while (i < n) {
        out_byte(ed, s[i]);
        i = i + 1;
    }
    return 0;
}

// Append a non-negative integer's decimal representation.
Long out_int(Ptr<Editor> ed, Long n) {
    if (n < 0) {
        out_byte(ed, cast<Byte>(45));   // '-'
        n = -n;
    }
    if (n == 0) {
        out_byte(ed, cast<Byte>(48));   // '0'
        return 0;
    }
    // Build digits in reverse, then emit forward.
    Byte buf[24];
    Long bn = 0;
    while (n > 0) {
        Long d = n - (n / 10) * 10;
        buf[bn] = cast<Byte>(48 + d);
        bn = bn + 1;
        n = n / 10;
    }
    Long bi = bn - 1;
    while (bi >= 0) {
        out_byte(ed, buf[bi]);
        bi = bi - 1;
    }
    return 0;
}

Long out_flush(Ptr<Editor> ed) {
    lazyc_sys_write(1, (*ed).out_buf, (*ed).out_len);
    (*ed).out_len = 0;
    return 0;
}


// ============================================================
// TERMINAL CONTROL
// ============================================================

// Read a 4-byte little-endian unsigned value at termios+offset
// and return it as a Long.
Long termios_read_flag(Ptr<Byte> t, Long offset) {
    Long b0 = cast<Long>(t[offset + 0]);
    Long b1 = cast<Long>(t[offset + 1]);
    Long b2 = cast<Long>(t[offset + 2]);
    Long b3 = cast<Long>(t[offset + 3]);
    // Manual shift: (b3<<24)|(b2<<16)|(b1<<8)|b0
    Long r = b3;
    r = r * 256 + b2;
    r = r * 256 + b1;
    r = r * 256 + b0;
    return r;
}

// Write a 32-bit unsigned value v to termios+offset (little-endian).
Long termios_write_flag(Ptr<Byte> t, Long offset, Long v) {
    t[offset + 0] = cast<Byte>(v - (v / 256) * 256);
    Long v1 = v / 256;
    t[offset + 1] = cast<Byte>(v1 - (v1 / 256) * 256);
    Long v2 = v1 / 256;
    t[offset + 2] = cast<Byte>(v2 - (v2 / 256) * 256);
    Long v3 = v2 / 256;
    t[offset + 3] = cast<Byte>(v3 - (v3 / 256) * 256);
    return 0;
}

// Bitwise AND on Longs by repeated shift+test (no & operator in lazyc).
// Both inputs must be non-negative and fit in 32 bits for our use.
Long bit_and_not(Long a, Long mask_to_clear) {
    // Returns a with the bits in mask_to_clear cleared.
    // Implemented as: for each bit position, copy a's bit only if the
    // corresponding bit in mask_to_clear is 0.
    Long result = 0;
    Long bit = 1;
    Long i = 0;
    while (i < 32) {
        Long a_has   = a   - (a   / (bit * 2)) * (bit * 2);
        Long m_has   = mask_to_clear - (mask_to_clear / (bit * 2)) * (bit * 2);
        // is the (i)-th bit set in a?
        Long a_bit   = a_has   / bit;
        Long m_bit   = m_has   / bit;
        if (a_bit != 0) {
            if (m_bit == 0) {
                result = result + bit;
            }
        }
        bit = bit * 2;
        i = i + 1;
    }
    return result;
}

// Save current termios into ed.saved_termios and switch to raw mode.
Long enable_raw_mode(Ptr<Editor> ed) {
    Ptr<Byte> saved = alloc(TERMIOS_SIZE());
    Long rc1 = lazyc_sys_ioctl(0, TCGETS(), saved);
    if (rc1 < 0) {
        free(saved);
        (*ed).saved_termios = cast<Ptr<Byte>>(null);
        return rc1;
    }
    (*ed).saved_termios = saved;

    // Make a working copy.
    Ptr<Byte> raw = alloc(TERMIOS_SIZE());
    Long i = 0;
    while (i < TERMIOS_SIZE()) {
        raw[i] = saved[i];
        i = i + 1;
    }

    // c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
    Long iflag = termios_read_flag(raw, TERMIOS_IFLAG());
    Long imask = BRKINT() + ICRNL() + INPCK() + ISTRIP() + IXON();
    iflag = bit_and_not(iflag, imask);
    termios_write_flag(raw, TERMIOS_IFLAG(), iflag);

    // c_oflag &= ~OPOST
    Long oflag = termios_read_flag(raw, TERMIOS_OFLAG());
    oflag = bit_and_not(oflag, OPOST());
    termios_write_flag(raw, TERMIOS_OFLAG(), oflag);

    // c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG)
    Long lflag = termios_read_flag(raw, TERMIOS_LFLAG());
    Long lmask = ECHO_FL() + ICANON() + IEXTEN() + ISIG();
    lflag = bit_and_not(lflag, lmask);
    termios_write_flag(raw, TERMIOS_LFLAG(), lflag);

    // c_cc[VMIN] = 1 (block until at least 1 byte)
    // c_cc[VTIME] = 0 (no timeout)
    raw[TERMIOS_CC() + VMIN_OFFSET()]  = cast<Byte>(1);
    raw[TERMIOS_CC() + VTIME_OFFSET()] = cast<Byte>(0);

    Long rc2 = lazyc_sys_ioctl(0, TCSETS(), raw);
    free(raw);
    return rc2;
}

Long disable_raw_mode(Ptr<Editor> ed) {
    if ((*ed).saved_termios == null) { return 0; }
    lazyc_sys_ioctl(0, TCSETS(), (*ed).saved_termios);
    return 0;
}

// winsize struct: 4 unsigned shorts (rows, cols, xpx, ypx).
Long get_window_size(Ptr<Editor> ed) {
    Ptr<Byte> ws = alloc(8);
    Long rc = lazyc_sys_ioctl(1, TIOCGWINSZ(), ws);
    if (rc < 0) {
        free(ws);
        // Fallback to 24x80.
        (*ed).screen_rows = 24;
        (*ed).screen_cols = 80;
        return 0;
    }
    Long rows = cast<Long>(ws[0]) + cast<Long>(ws[1]) * 256;
    Long cols = cast<Long>(ws[2]) + cast<Long>(ws[3]) * 256;
    free(ws);
    if (rows < 1) { rows = 24; }
    if (cols < 1) { cols = 80; }
    (*ed).screen_rows = rows;
    (*ed).screen_cols = cols;
    return 0;
}


// ============================================================
// INPUT
// ============================================================

// Pushback: a held byte value lets us "un-read" one byte after we've
// consumed it. Used to disambiguate "user pressed Esc" from "Esc was
// the lead byte of an arrow-key escape sequence" — when we read the
// byte after Esc and it isn't '[', we put it back so the next read
// returns it. Storage lives on the Editor struct.

Long read_byte_ed(Ptr<Editor> ed) {
    Long held = (*ed).pushback;
    if (held >= 0) {
        (*ed).pushback = -1;
        return held;
    }
    Ptr<Byte> buf = alloc(1);
    Long n = lazyc_sys_read(0, buf, 1);
    Long result = -1;
    if (n == 1) { result = cast<Long>(buf[0]); }
    free(buf);
    return result;
}

Long read_key_ed(Ptr<Editor> ed) {
    Long c = read_byte_ed(ed);
    if (c < 0) { return KEY_NONE(); }
    if (c != 27) { return c; }
    Long c2 = read_byte_ed(ed);
    if (c2 < 0)   { return KEY_ESC(); }
    if (c2 != 91) {
        // Bare Esc followed by another byte: push it back.
        (*ed).pushback = c2;
        return KEY_ESC();
    }
    Long c3 = read_byte_ed(ed);
    if (c3 < 0)   { return KEY_ESC(); }
    if (c3 == 65) { return KEY_UP(); }
    if (c3 == 66) { return KEY_DOWN(); }
    if (c3 == 67) { return KEY_RIGHT(); }
    if (c3 == 68) { return KEY_LEFT(); }
    return KEY_ESC();
}


// ============================================================
// FILE I/O
// ============================================================

// Load file at path into ed's lines. If file doesn't exist, leave the
// editor with one empty line.
Long ed_load_file(Ptr<Editor> ed, Ptr<Byte> path) {
    Ptr<Byte> data = readf(cast<String>(path));
    if (data == null) {
        ed_append_empty_line(ed);
        return 0;
    }
    // Determine length.
    Long n = 0;
    while (cast<Long>(data[n]) != 0) { n = n + 1; }
    // Split on '\n' into lines. Each line excludes the newline.
    Long start = 0;
    Long i = 0;
    while (i < n) {
        if (cast<Long>(data[i]) == 10) {
            ed_append_empty_line(ed);
            Ptr<Line> ln = ed_line(ed, (*ed).num_lines - 1);
            Long j = start;
            while (j < i) {
                line_push_byte(ln, data[j]);
                j = j + 1;
            }
            start = i + 1;
        }
        i = i + 1;
    }
    // Trailing portion (no newline at end).
    if (start < n) {
        ed_append_empty_line(ed);
        Ptr<Line> tln = ed_line(ed, (*ed).num_lines - 1);
        Long k = start;
        while (k < n) {
            line_push_byte(tln, data[k]);
            k = k + 1;
        }
    }
    if ((*ed).num_lines == 0) {
        ed_append_empty_line(ed);
    }
    free(data);
    return 0;
}

// Save ed's lines to the given path. If path is null, uses ed.filename.
// Returns 0 on success, 1 if no filename available, 2 if write failed.
Long ed_save_file_to(Ptr<Editor> ed, Ptr<Byte> path) {
    Ptr<Byte> target = path;
    if (target == null) { target = (*ed).filename; }
    if (target == null) { return 1; }
    // Compute total bytes needed: sum of line lengths plus newlines.
    Long total = 0;
    Long i = 0;
    while (i < (*ed).num_lines) {
        Ptr<Line> ln = ed_line(ed, i);
        total = total + (*ln).len + 1;
        i = i + 1;
    }
    Ptr<Byte> buf = alloc(total + 1);
    Long pos = 0;
    Long j = 0;
    while (j < (*ed).num_lines) {
        Ptr<Line> ln2 = ed_line(ed, j);
        Long k = 0;
        while (k < (*ln2).len) {
            buf[pos] = (*ln2).data[k];
            pos = pos + 1;
            k = k + 1;
        }
        buf[pos] = cast<Byte>(10);   // '\n'
        pos = pos + 1;
        j = j + 1;
    }
    buf[pos] = cast<Byte>(0);
    Boolean ok = writef(cast<String>(target), buf);
    free(buf);
    if (!ok) { return 2; }
    (*ed).dirty = false;
    // If path was supplied and ed had no filename, adopt it.
    if (path != null) {
        if ((*ed).filename == null) {
            Long pn = 0;
            while (cast<Long>(path[pn]) != 0) { pn = pn + 1; }
            Ptr<Byte> fn = alloc(pn + 1);
            Long pi = 0;
            while (pi < pn) { fn[pi] = path[pi]; pi = pi + 1; }
            fn[pn] = cast<Byte>(0);
            (*ed).filename = fn;
            (*ed).filename_len = pn;
        }
    }
    return 0;
}

// Backward-compat wrapper used from internal call sites that don't yet
// pass a path.
Boolean ed_save_file(Ptr<Editor> ed) {
    Long rc = ed_save_file_to(ed, cast<Ptr<Byte>>(null));
    if (rc == 0) { return true; }
    return false;
}


// ============================================================
// STATUS MESSAGE
// ============================================================

Long set_status(Ptr<Editor> ed, Ptr<Byte> msg) {
    if ((*ed).status_msg != null) { free((*ed).status_msg); }
    Long n = 0;
    while (cast<Long>(msg[n]) != 0) { n = n + 1; }
    Ptr<Byte> nb = alloc(n + 1);
    Long i = 0;
    while (i < n) { nb[i] = msg[i]; i = i + 1; }
    nb[n] = cast<Byte>(0);
    (*ed).status_msg = nb;
    (*ed).status_len = n;
    return 0;
}


// ============================================================
// SCREEN RENDERING
// ============================================================

// Make sure cursor is visible by adjusting row_off / col_off.
Long ed_scroll(Ptr<Editor> ed) {
    Long edit_rows = (*ed).screen_rows - 2;   // last 2 rows = status + cmd
    if (edit_rows < 1) { edit_rows = 1; }
    if ((*ed).cy < (*ed).row_off) {
        (*ed).row_off = (*ed).cy;
    }
    if ((*ed).cy >= (*ed).row_off + edit_rows) {
        (*ed).row_off = (*ed).cy - edit_rows + 1;
    }
    if ((*ed).cx < (*ed).col_off) {
        (*ed).col_off = (*ed).cx;
    }
    if ((*ed).cx >= (*ed).col_off + (*ed).screen_cols) {
        (*ed).col_off = (*ed).cx - (*ed).screen_cols + 1;
    }
    return 0;
}

Long ed_draw_lines(Ptr<Editor> ed) {
    Long edit_rows = (*ed).screen_rows - 2;
    if (edit_rows < 1) { edit_rows = 1; }
    Long y = 0;
    while (y < edit_rows) {
        Long file_row = (*ed).row_off + y;
        if (file_row < (*ed).num_lines) {
            Ptr<Line> ln = ed_line(ed, file_row);
            Long len_visible = (*ln).len - (*ed).col_off;
            if (len_visible > 0) {
                if (len_visible > (*ed).screen_cols) {
                    len_visible = (*ed).screen_cols;
                }
                Long k = 0;
                while (k < len_visible) {
                    Byte b = (*ln).data[(*ed).col_off + k];
                    Long bv = cast<Long>(b);
                    if (bv == 9) {
                        // Tab -> 4 spaces (basic).
                        out_byte(ed, cast<Byte>(32));
                        out_byte(ed, cast<Byte>(32));
                        out_byte(ed, cast<Byte>(32));
                        out_byte(ed, cast<Byte>(32));
                    } else {
                        if (bv < 32) {
                            // Non-printable -> '?'.
                            out_byte(ed, cast<Byte>(63));
                        } else {
                            out_byte(ed, b);
                        }
                    }
                    k = k + 1;
                }
            }
        } else {
            // Past end of buffer.
            out_byte(ed, cast<Byte>(126));   // '~'
        }
        // Erase to end of line and CRLF.
        out_str(ed, cast<Ptr<Byte>>("\x1b[K\r\n"));
        y = y + 1;
    }
    return 0;
}

Long ed_draw_status(Ptr<Editor> ed) {
    // Reverse-video status line.
    out_str(ed, cast<Ptr<Byte>>("\x1b[7m"));
    // Mode label.
    Long mode = (*ed).mode;
    if (mode == MODE_NORMAL())  { out_str(ed, cast<Ptr<Byte>>(" NORMAL ")); }
    if (mode == MODE_INSERT())  { out_str(ed, cast<Ptr<Byte>>(" INSERT ")); }
    if (mode == MODE_COMMAND()) { out_str(ed, cast<Ptr<Byte>>(" COMMAND ")); }
    out_byte(ed, cast<Byte>(32));
    // Filename or [No Name].
    if ((*ed).filename != null) {
        out_str(ed, (*ed).filename);
    } else {
        out_str(ed, cast<Ptr<Byte>>("[No Name]"));
    }
    if ((*ed).dirty) {
        out_str(ed, cast<Ptr<Byte>>(" [+]"));
    }
    // Right-align cursor info: "lN/M cC".
    // Just append spaces, then position.
    out_str(ed, cast<Ptr<Byte>>("  "));
    out_str(ed, cast<Ptr<Byte>>("L"));
    out_int(ed, (*ed).cy + 1);
    out_str(ed, cast<Ptr<Byte>>("/"));
    out_int(ed, (*ed).num_lines);
    out_str(ed, cast<Ptr<Byte>>(" C"));
    out_int(ed, (*ed).cx + 1);
    out_str(ed, cast<Ptr<Byte>>("\x1b[K\x1b[m\r\n"));
    return 0;
}

Long ed_draw_cmdline(Ptr<Editor> ed) {
    // Last row: command buffer or status message.
    if ((*ed).mode == MODE_COMMAND()) {
        out_byte(ed, cast<Byte>(58));   // ':'
        Ptr<Line> cmd = (*ed).cmd_buf;
        Long k = 0;
        while (k < (*cmd).len) {
            out_byte(ed, (*cmd).data[k]);
            k = k + 1;
        }
    } else {
        if ((*ed).status_msg != null) {
            if ((*ed).status_len > 0) {
                Long maxlen = (*ed).status_len;
                if (maxlen > (*ed).screen_cols) { maxlen = (*ed).screen_cols; }
                out_bytes(ed, (*ed).status_msg, maxlen);
            }
        }
    }
    out_str(ed, cast<Ptr<Byte>>("\x1b[K"));
    return 0;
}

Long ed_render(Ptr<Editor> ed) {
    ed_scroll(ed);
    out_str(ed, cast<Ptr<Byte>>("\x1b[?25l"));   // hide cursor
    out_str(ed, cast<Ptr<Byte>>("\x1b[H"));      // home
    ed_draw_lines(ed);
    ed_draw_status(ed);
    ed_draw_cmdline(ed);
    // Position cursor.
    out_str(ed, cast<Ptr<Byte>>("\x1b["));
    if ((*ed).mode == MODE_COMMAND()) {
        out_int(ed, (*ed).screen_rows);
        out_str(ed, cast<Ptr<Byte>>(";"));
        out_int(ed, (*((*ed).cmd_buf)).len + 2);   // +1 for the ':' +1 for 1-based
    } else {
        out_int(ed, (*ed).cy - (*ed).row_off + 1);
        out_str(ed, cast<Ptr<Byte>>(";"));
        out_int(ed, (*ed).cx - (*ed).col_off + 1);
    }
    out_str(ed, cast<Ptr<Byte>>("H"));
    out_str(ed, cast<Ptr<Byte>>("\x1b[?25h"));   // show cursor
    out_flush(ed);
    return 0;
}


// ============================================================
// EDITING OPERATIONS
// ============================================================

// Clamp cursor to a valid position on its current line.
Long ed_clamp_cursor(Ptr<Editor> ed) {
    if ((*ed).cy < 0) { (*ed).cy = 0; }
    if ((*ed).cy >= (*ed).num_lines) { (*ed).cy = (*ed).num_lines - 1; }
    Ptr<Line> ln = ed_line(ed, (*ed).cy);
    Long max_x = (*ln).len;
    if ((*ed).mode == MODE_NORMAL()) {
        // In NORMAL, cursor sits ON a char (not past end), unless line is empty.
        if (max_x > 0) { max_x = max_x - 1; }
    }
    if ((*ed).cx < 0) { (*ed).cx = 0; }
    if ((*ed).cx > max_x) { (*ed).cx = max_x; }
    return 0;
}

Long ed_move_left(Ptr<Editor> ed) {
    if ((*ed).cx > 0) { (*ed).cx = (*ed).cx - 1; }
    return 0;
}

Long ed_move_right(Ptr<Editor> ed) {
    Ptr<Line> ln = ed_line(ed, (*ed).cy);
    Long max_x = (*ln).len;
    if ((*ed).mode == MODE_NORMAL()) {
        if (max_x > 0) { max_x = max_x - 1; }
    }
    if ((*ed).cx < max_x) { (*ed).cx = (*ed).cx + 1; }
    return 0;
}

Long ed_move_up(Ptr<Editor> ed) {
    if ((*ed).cy > 0) {
        (*ed).cy = (*ed).cy - 1;
        ed_clamp_cursor(ed);
    }
    return 0;
}

Long ed_move_down(Ptr<Editor> ed) {
    if ((*ed).cy < (*ed).num_lines - 1) {
        (*ed).cy = (*ed).cy + 1;
        ed_clamp_cursor(ed);
    }
    return 0;
}

Long ed_insert_char(Ptr<Editor> ed, Byte b) {
    Ptr<Line> ln = ed_line(ed, (*ed).cy);
    line_insert(ln, (*ed).cx, b);
    (*ed).cx = (*ed).cx + 1;
    (*ed).dirty = true;
    return 0;
}

Long ed_insert_newline(Ptr<Editor> ed) {
    // Split current line at cx; the part after cx becomes a new line below.
    Ptr<Line> ln = ed_line(ed, (*ed).cy);
    Long split = (*ed).cx;
    Long old_len = (*ln).len;
    ed_insert_line_at(ed, (*ed).cy + 1);
    // ed_insert_line_at may have moved memory; refetch ln.
    ln = ed_line(ed, (*ed).cy);
    Ptr<Line> nln = ed_line(ed, (*ed).cy + 1);
    Long k = split;
    while (k < old_len) {
        line_push_byte(nln, (*ln).data[k]);
        k = k + 1;
    }
    (*ln).len = split;
    (*ed).cy = (*ed).cy + 1;
    (*ed).cx = 0;
    (*ed).dirty = true;
    return 0;
}

Long ed_backspace(Ptr<Editor> ed) {
    if ((*ed).cx > 0) {
        Ptr<Line> ln = ed_line(ed, (*ed).cy);
        line_delete(ln, (*ed).cx - 1);
        (*ed).cx = (*ed).cx - 1;
        (*ed).dirty = true;
        return 0;
    }
    if ((*ed).cy > 0) {
        // Join with previous line.
        Ptr<Line> prev = ed_line(ed, (*ed).cy - 1);
        Ptr<Line> cur  = ed_line(ed, (*ed).cy);
        Long old_prev_len = (*prev).len;
        Long k = 0;
        while (k < (*cur).len) {
            line_push_byte(prev, (*cur).data[k]);
            k = k + 1;
        }
        ed_delete_line_at(ed, (*ed).cy);
        (*ed).cy = (*ed).cy - 1;
        (*ed).cx = old_prev_len;
        (*ed).dirty = true;
    }
    return 0;
}

Long ed_delete_char_under_cursor(Ptr<Editor> ed) {
    Ptr<Line> ln = ed_line(ed, (*ed).cy);
    if ((*ln).len == 0) { return 0; }
    line_delete(ln, (*ed).cx);
    (*ed).dirty = true;
    ed_clamp_cursor(ed);
    return 0;
}

Long ed_delete_current_line(Ptr<Editor> ed) {
    if ((*ed).num_lines <= 1) {
        // Don't drop to zero lines; just empty the only line.
        Ptr<Line> ln = ed_line(ed, 0);
        (*ln).len = 0;
        (*ed).cx = 0;
        (*ed).cy = 0;
    } else {
        ed_delete_line_at(ed, (*ed).cy);
        if ((*ed).cy >= (*ed).num_lines) { (*ed).cy = (*ed).num_lines - 1; }
        (*ed).cx = 0;
    }
    (*ed).dirty = true;
    return 0;
}

Long ed_open_line_below(Ptr<Editor> ed) {
    ed_insert_line_at(ed, (*ed).cy + 1);
    (*ed).cy = (*ed).cy + 1;
    (*ed).cx = 0;
    (*ed).mode = MODE_INSERT();
    (*ed).dirty = true;
    return 0;
}


// ============================================================
// COMMAND-MODE EXECUTION
// ============================================================

// Returns true if the buffer contents equal the given null-terminated string.
Boolean cmd_eq(Ptr<Line> cmd, Ptr<Byte> s) {
    Long n = 0;
    while (cast<Long>(s[n]) != 0) { n = n + 1; }
    if (n != (*cmd).len) { return false; }
    Long i = 0;
    while (i < n) {
        if (cast<Long>(s[i]) != cast<Long>((*cmd).data[i])) { return false; }
        i = i + 1;
    }
    return true;
}

// Returns true if cmd starts with the null-terminated prefix `pfx` and
// the next char (if any) is a space. Also writes the byte index after
// the space into *out_arg_start (or cmd.len if no argument).
Boolean cmd_starts_with(Ptr<Line> cmd, Ptr<Byte> pfx, Ptr<Long> out_arg_start) {
    Long pn = 0;
    while (cast<Long>(pfx[pn]) != 0) { pn = pn + 1; }
    if ((*cmd).len < pn) { return false; }
    Long i = 0;
    while (i < pn) {
        if (cast<Long>(pfx[i]) != cast<Long>((*cmd).data[i])) { return false; }
        i = i + 1;
    }
    // Either end-of-cmd or a space.
    if ((*cmd).len == pn) {
        *out_arg_start = pn;
        return true;
    }
    if (cast<Long>((*cmd).data[pn]) == 32) {
        *out_arg_start = pn + 1;
        return true;
    }
    return false;
}

// Extract a freshly allocated null-terminated string from cmd[start..len).
// Trims leading/trailing spaces. Returns null if the range is empty after
// trimming.
Ptr<Byte> cmd_extract_arg(Ptr<Line> cmd, Long start) {
    Long s = start;
    Long e = (*cmd).len;
    while (s < e) {
        if (cast<Long>((*cmd).data[s]) != 32) { break; }
        s = s + 1;
    }
    while (e > s) {
        if (cast<Long>((*cmd).data[e - 1]) != 32) { break; }
        e = e - 1;
    }
    if (e <= s) { return cast<Ptr<Byte>>(null); }
    Long n = e - s;
    Ptr<Byte> out = alloc(n + 1);
    Long i = 0;
    while (i < n) {
        out[i] = (*cmd).data[s + i];
        i = i + 1;
    }
    out[n] = cast<Byte>(0);
    return out;
}

Long ed_exec_command(Ptr<Editor> ed) {
    Ptr<Line> cmd = (*ed).cmd_buf;
    Long arg_start = 0;
    Boolean handled = false;

    // ":q" — quit (refuses if dirty).
    if (cmd_eq(cmd, cast<Ptr<Byte>>("q"))) {
        if ((*ed).dirty) {
            set_status(ed, cast<Ptr<Byte>>("E37: No write since last change (use :q! to override)"));
        } else {
            (*ed).quitting = true;
        }
        handled = true;
    }

    // ":q!" — quit, discarding changes.
    if (!handled) {
        if (cmd_eq(cmd, cast<Ptr<Byte>>("q!"))) {
            (*ed).quitting = true;
            handled = true;
        }
    }

    // ":wq" or ":wq <name>" — write then quit.
    if (!handled) {
        if (cmd_starts_with(cmd, cast<Ptr<Byte>>("wq"), &arg_start)) {
            Ptr<Byte> arg = cmd_extract_arg(cmd, arg_start);
            Long rc = ed_save_file_to(ed, arg);
            if (arg != null) { free(arg); }
            if (rc == 0) {
                (*ed).quitting = true;
            } else {
                if (rc == 1) {
                    set_status(ed, cast<Ptr<Byte>>("E32: No file name"));
                } else {
                    set_status(ed, cast<Ptr<Byte>>("E212: Can't open file for writing"));
                }
            }
            handled = true;
        }
    }

    // ":w" or ":w <name>" — write.
    if (!handled) {
        if (cmd_starts_with(cmd, cast<Ptr<Byte>>("w"), &arg_start)) {
            Ptr<Byte> arg2 = cmd_extract_arg(cmd, arg_start);
            Long rc2 = ed_save_file_to(ed, arg2);
            if (arg2 != null) { free(arg2); }
            if (rc2 == 0) {
                set_status(ed, cast<Ptr<Byte>>("written"));
            } else {
                if (rc2 == 1) {
                    set_status(ed, cast<Ptr<Byte>>("E32: No file name"));
                } else {
                    set_status(ed, cast<Ptr<Byte>>("E212: Can't open file for writing"));
                }
            }
            handled = true;
        }
    }

    // ":e <name>" — set the editor's filename (does not load anything).
    if (!handled) {
        if (cmd_starts_with(cmd, cast<Ptr<Byte>>("e"), &arg_start)) {
            Ptr<Byte> arg3 = cmd_extract_arg(cmd, arg_start);
            if (arg3 == null) {
                set_status(ed, cast<Ptr<Byte>>("E32: No file name"));
            } else {
                if ((*ed).filename != null) { free((*ed).filename); }
                Long an = 0;
                while (cast<Long>(arg3[an]) != 0) { an = an + 1; }
                (*ed).filename = arg3;
                (*ed).filename_len = an;
                set_status(ed, cast<Ptr<Byte>>("filename set"));
            }
            handled = true;
        }
    }

    if (!handled) {
        set_status(ed, cast<Ptr<Byte>>("E492: Not an editor command"));
    }

    (*cmd).len = 0;
    (*ed).mode = MODE_NORMAL();
    return 0;
}


// ============================================================
// KEY DISPATCH
// ============================================================

// Pending second key for two-key motions: 0=none, 1='d' pending (so 'dd'),
// 2='g' pending (so 'gg').
Long ed_normal_key(Ptr<Editor> ed, Long key, Long pending) {
    // Arrow keys -> hjkl.
    if (key == KEY_LEFT())  { ed_move_left(ed);  return 0; }
    if (key == KEY_RIGHT()) { ed_move_right(ed); return 0; }
    if (key == KEY_UP())    { ed_move_up(ed);    return 0; }
    if (key == KEY_DOWN())  { ed_move_down(ed);  return 0; }

    if (pending == 1) {
        // We were waiting for the second 'd' of 'dd'.
        if (key == 100) {                // 'd'
            ed_delete_current_line(ed);
        }
        return 0;
    }
    if (pending == 2) {
        if (key == 103) {                // 'g'
            (*ed).cy = 0;
            (*ed).cx = 0;
        }
        return 0;
    }

    if (key == 104) { ed_move_left(ed);  return 0; }   // 'h'
    if (key == 106) { ed_move_down(ed);  return 0; }   // 'j'
    if (key == 107) { ed_move_up(ed);    return 0; }   // 'k'
    if (key == 108) { ed_move_right(ed); return 0; }   // 'l'

    if (key == 105) { (*ed).mode = MODE_INSERT(); return 0; }   // 'i'
    if (key == 97)  {                                            // 'a'
        ed_move_right(ed);
        (*ed).mode = MODE_INSERT();
        return 0;
    }
    if (key == 65) {                                             // 'A'
        Ptr<Line> ln_a = ed_line(ed, (*ed).cy);
        (*ed).cx = (*ln_a).len;
        (*ed).mode = MODE_INSERT();
        return 0;
    }
    if (key == 73) {                                             // 'I'
        (*ed).cx = 0;
        (*ed).mode = MODE_INSERT();
        return 0;
    }
    if (key == 111) { ed_open_line_below(ed); return 0; }        // 'o'

    if (key == 120) { ed_delete_char_under_cursor(ed); return 0; }  // 'x'

    if (key == 48)  { (*ed).cx = 0; return 0; }                  // '0'
    if (key == 36)  {                                             // '$'
        Ptr<Line> ln_d = ed_line(ed, (*ed).cy);
        if ((*ln_d).len > 0) {
            (*ed).cx = (*ln_d).len - 1;
        } else {
            (*ed).cx = 0;
        }
        return 0;
    }
    if (key == 71) { (*ed).cy = (*ed).num_lines - 1; ed_clamp_cursor(ed); return 0; } // 'G'

    if (key == 58) { (*ed).mode = MODE_COMMAND(); return 0; }   // ':'

    return 0;
}

Long ed_insert_key(Ptr<Editor> ed, Long key) {
    if (key == KEY_ESC()) {
        (*ed).mode = MODE_NORMAL();
        ed_clamp_cursor(ed);
        return 0;
    }
    if (key == KEY_LEFT())  { ed_move_left(ed);  return 0; }
    if (key == KEY_RIGHT()) { ed_move_right(ed); return 0; }
    if (key == KEY_UP())    { ed_move_up(ed);    return 0; }
    if (key == KEY_DOWN())  { ed_move_down(ed);  return 0; }
    if (key == KEY_BACKSPACE()) { ed_backspace(ed); return 0; }
    if (key == 8)            { ed_backspace(ed); return 0; }   // Ctrl-H sometimes
    if (key == KEY_ENTER())  { ed_insert_newline(ed); return 0; }
    if (key == 10)           { ed_insert_newline(ed); return 0; }

    // Printable: 32..126, plus tab.
    if (key == 9) { ed_insert_char(ed, cast<Byte>(9)); return 0; }
    if (key >= 32) {
        if (key <= 126) {
            ed_insert_char(ed, cast<Byte>(key));
        }
    }
    return 0;
}

Long ed_command_key(Ptr<Editor> ed, Long key) {
    if (key == KEY_ESC()) {
        Ptr<Line> cmd = (*ed).cmd_buf;
        (*cmd).len = 0;
        (*ed).mode = MODE_NORMAL();
        return 0;
    }
    if (key == KEY_ENTER()) { ed_exec_command(ed); return 0; }
    if (key == 10)          { ed_exec_command(ed); return 0; }
    if (key == KEY_BACKSPACE()) {
        Ptr<Line> cmd2 = (*ed).cmd_buf;
        if ((*cmd2).len > 0) {
            (*cmd2).len = (*cmd2).len - 1;
        } else {
            (*ed).mode = MODE_NORMAL();
        }
        return 0;
    }
    if (key >= 32) {
        if (key <= 126) {
            line_push_byte((*ed).cmd_buf, cast<Byte>(key));
        }
    }
    return 0;
}


// ============================================================
// MAIN
// ============================================================

Long ed_init(Ptr<Editor> ed) {
    (*ed).lines = cast<Ptr<Byte>>(null);
    (*ed).num_lines = 0;
    (*ed).cap_lines = 0;
    (*ed).cx = 0;
    (*ed).cy = 0;
    (*ed).row_off = 0;
    (*ed).col_off = 0;
    (*ed).screen_rows = 24;
    (*ed).screen_cols = 80;
    (*ed).mode = MODE_NORMAL();
    (*ed).dirty = false;
    (*ed).quitting = false;
    (*ed).filename = cast<Ptr<Byte>>(null);
    (*ed).filename_len = 0;
    (*ed).status_msg = cast<Ptr<Byte>>(null);
    (*ed).status_len = 0;
    (*ed).out_buf = cast<Ptr<Byte>>(null);
    (*ed).out_len = 0;
    (*ed).out_cap = 0;
    (*ed).saved_termios = cast<Ptr<Byte>>(null);
    (*ed).pushback = -1;

    // Allocate cmd_buf as a Line.
    Ptr<Byte> cb_raw = alloc(24);
    Ptr<Line> cb = cast<Ptr<Line>>(cb_raw);
    line_init(cb);
    (*ed).cmd_buf = cb;
    return 0;
}

Long main() {
    Editor ed;
    Ptr<Editor> edp = &ed;
    ed_init(edp);

    // Filename from argv[1] if present.
    if (argc() >= 2) {
        Ptr<Byte> path = argv(1);
        Long pn = 0;
        while (cast<Long>(path[pn]) != 0) { pn = pn + 1; }
        Ptr<Byte> fn = alloc(pn + 1);
        Long pi = 0;
        while (pi < pn) { fn[pi] = path[pi]; pi = pi + 1; }
        fn[pn] = cast<Byte>(0);
        ed.filename = fn;
        ed.filename_len = pn;
        ed_load_file(edp, path);
    } else {
        ed_append_empty_line(edp);
    }

    if (enable_raw_mode(edp) < 0) {
        println("error: could not enable raw mode (not a tty?)");
        return 1;
    }
    get_window_size(edp);
    set_status(edp, cast<Ptr<Byte>>("HELP: i=insert  Esc=normal  :w=save  :q=quit"));

    // Main loop.
    while (!ed.quitting) {
        ed_render(edp);
        Long key = read_key_ed(edp);
        if (key == KEY_NONE()) { continue; }

        // If we're tracking a 2-key motion (dd or gg), check for it.
        Long pending = 0;
        if (ed.mode == MODE_NORMAL()) {
            if (key == 100) {              // 'd'
                ed_render(edp);
                Long k2 = read_key_ed(edp);
                ed_normal_key(edp, k2, 1);
                continue;
            }
            if (key == 103) {              // 'g'
                ed_render(edp);
                Long k3 = read_key_ed(edp);
                ed_normal_key(edp, k3, 2);
                continue;
            }
        }

        Long mode = ed.mode;
        if (mode == MODE_NORMAL())  { ed_normal_key(edp, key, 0); }
        if (mode == MODE_INSERT())  { ed_insert_key(edp, key); }
        if (mode == MODE_COMMAND()) { ed_command_key(edp, key); }
    }

    disable_raw_mode(edp);
    // Clear screen on exit.
    lazyc_sys_write(1, cast<Ptr<Byte>>("\x1b[2J\x1b[H"), 7);
    return 0;
}
