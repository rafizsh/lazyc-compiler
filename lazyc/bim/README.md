# bim — a small vim-like editor written in lazyc

bim is a modal text editor implemented in lazyc. It's intentionally
small (one source file, around 750 lines of lazyc) but supports
enough of vim's normal/insert/command-mode model to actually edit files
with it.

It is not a vim clone. It implements roughly the subset that fits in
one head and one source file. If you want full vim, use vim.

## Build

From the repository root:

```sh
./build.sh                    # build the lazyc compiler + runtime
bim/build-bim.sh              # build bim
bim/bim path/to/file.txt
```

`build-bim.sh` requires `nasm` and `ld`, plus a previously-built
`build/lazyc` and `build/runtime.o`.

## Modes

Like vim, bim is modal:

- **NORMAL** — the default. Keys move the cursor and trigger commands.
- **INSERT** — keys are typed into the buffer.
- **COMMAND** — line-mode for `:w`, `:q`, etc.

The current mode is shown on the status line.

## Keys

### NORMAL mode

| Key      | Action                              |
|----------|-------------------------------------|
| `h`      | move cursor left                    |
| `j`      | move cursor down                    |
| `k`      | move cursor up                      |
| `l`      | move cursor right                   |
| arrows   | also move (up/down/left/right)      |
| `0`      | go to start of line                 |
| `$`      | go to end of line                   |
| `gg`     | go to first line                    |
| `G`      | go to last line                     |
| `i`      | enter INSERT at cursor              |
| `I`      | enter INSERT at start of line       |
| `a`      | enter INSERT after cursor           |
| `A`      | enter INSERT at end of line         |
| `o`      | open a new line below, INSERT       |
| `x`      | delete character under cursor       |
| `dd`     | delete current line                 |
| `:`      | enter COMMAND mode                  |

### INSERT mode

| Key       | Action                              |
|-----------|-------------------------------------|
| (typed)   | insert character                    |
| Enter     | split line at cursor (insert newline) |
| Backspace | delete previous character; joins lines at column 0 |
| arrows    | move cursor (still in INSERT)       |
| Esc       | return to NORMAL                    |

### COMMAND mode

After pressing `:` in NORMAL, type a command and press Enter:

| Command          | Action                                              |
|------------------|-----------------------------------------------------|
| `:w`             | write to disk (uses current filename)               |
| `:w <path>`      | write to <path>; if buffer was unnamed, adopt it    |
| `:wq`            | write and quit                                      |
| `:wq <path>`     | write to <path>, then quit                          |
| `:e <path>`      | set the buffer's filename to <path> (no load)       |
| `:q`             | quit (refuses if unsaved changes)                   |
| `:q!`            | quit and discard unsaved changes                    |

Esc cancels command-mode without executing.

Errors are reported on the bottom row using vim-style codes:

| Code              | Meaning                                            |
|-------------------|----------------------------------------------------|
| `E32: No file name`            | tried `:w` without a filename and without an argument |
| `E37: No write since last change` | tried `:q` with unsaved changes — use `:q!` |
| `E212: Can't open file for writing` | the path exists but couldn't be written (permissions, missing directory, etc.) |
| `E492: Not an editor command`  | the command isn't recognized              |

## Status line

The bottom-second line shows: mode, filename (or `[No Name]`), a `[+]`
marker if there are unsaved changes, and the cursor's line-of-total
plus column position, e.g.:

```
 NORMAL  /etc/hosts [+]  L12/45 C8
```

The bottom row shows command-mode input or short status messages
("written", error from a command, etc.).

## Limitations

bim is a v1. It does NOT have:

- search (`/`, `?`, `n`, `N`)
- undo / redo (`u`, `Ctrl-r`)
- yank / paste (`y`, `p`)
- visual mode (`v`, `V`, `Ctrl-v`)
- multiple buffers, splits, or tabs
- syntax highlighting
- line numbers in the gutter
- ex-mode commands beyond `:w` / `:q` / `:wq` / `:q!`
- repeat counts (`3dd`, `5j`)
- `.` (repeat last change)
- registers
- key remapping or any kind of config file
- mouse support

Some of these are big projects in their own right (undo wants a
proper history representation; syntax highlighting wants a tokenizer
per language). Some are easy follow-ups.

## Implementation notes

- One source file: `bim.ml`. Around 750 lines of lazyc.
- Data model: array of lines, each line is a dynamic byte buffer.
  Editing within a line shifts bytes; insert/delete-line shifts the
  array of line structs.
- Terminal control: raw mode via `ioctl(TCSETS)` on stdin. Window
  size via `ioctl(TIOCGWINSZ)` on stdout. Output goes through a
  batched buffer that's flushed once per redraw to avoid flicker.
  Required adding `lazyc_sys_ioctl` (syscall 16) to the runtime.
- Input: byte-by-byte read from stdin, with a one-byte pushback so
  bare Esc can be disambiguated from Esc-as-escape-sequence-prefix.
- Bitwise operations: lazyc has no `&`, `|`, `~`, or shift operators.
  The termios flag manipulation uses a `bit_and_not(value, mask)`
  helper that walks bit positions one at a time.
- No global variables: lazyc doesn't have them. All state lives
  on the `Editor` struct, which `main` allocates on the stack and
  passes by pointer.

## Testing

bim is verified via a Python pty harness (not committed; see the
session transcripts). Tests exercise:

- Basic load / display: opens a file, screen contains the file's text
- INSERT mode: `A` then typing inserts at end of line
- Mode transitions: NORMAL -> INSERT -> NORMAL -> COMMAND
- Save and quit: `:wq` writes the buffer and exits cleanly
- Delete line: `dd` removes the current line
- Open new line: `o` creates a new line below and enters INSERT
- Top/bottom motion: `gg` / `G` jump to first / last line

Each test spawns bim under a real pty, sends keystrokes, captures the
screen output, then verifies the resulting file contents on disk.
