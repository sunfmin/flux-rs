# Running and configuring Flux

Commands, where options are set, checking part of a crate, and the editor.

## Commands

| Command | Does |
|---|---|
| `cargo flux` | Check the package. Same as `cargo flux check`. |
| `cargo flux check -p <pkg> --only-check='def:<name>'` | Check only the functions whose path contains `<name>`. Every error prints this command for its own function. |
| `cargo flux --workspace` | Check every package that enables Flux. |
| `cargo flux clean` | Remove what earlier runs produced. |
| `flux path/to/file.rs` | Check one file. Takes `rustc`'s flags, such as `--crate-type=lib`. |

`cargo flux` checks only packages with `enabled = true` under
`[package.metadata.flux]`; without it the package is compiled and nothing is
verified. In single-file mode the attributes are written with the `flux::`
prefix (`#[flux::spec(..)]`, `#![flux::defs { .. }]`) and need no dependency.

Never run `flux-driver` directly: it needs the compiler's libraries on its
path, which the two commands above arrange.

A run that restricts what is checked reports the rest as trusted in its
summary, so read the counts from a full run.

## Where options are set

The same options can be given in four places. Later ones win.

| Place | Scope | Form |
|---|---|---|
| `[package.metadata.flux]` in `Cargo.toml` | this package | `check_overflow = "strict"` |
| `flux.toml` beside it | every crate in the build, dependencies included | same keys |
| `FLUXFLAGS` environment variable | every `flux` invocation of this run | `FLUXFLAGS="-Ftimings" cargo flux` |
| `#[opts(..)]` on an item | that function, impl, trait or module | `#[opts(check_overflow = "strict")]` |

On the command line a flag is `-Fname=value`, with dashes where the keys have
underscores. A boolean flag may omit its value: `-Fscrape-quals`.

## Options

| Key | Values | Effect |
|---|---|---|
| `enabled` | bool | Verify this package. Required. |
| `check_overflow` | `none` `lazy` `strict` | How arithmetic overflow is treated. See `proving.md`. |
| `scrape_quals` | bool | Try the shapes found in specs as loop invariants. |
| `uif_ops` | `"*,/"` | Operators to treat as unknown functions. See `spec-functions.md`. |
| `no_panic` | bool | Every function is `no_panic` unless it opts out. |
| `default_trusted` | bool | Everything is trusted unless marked `#[trusted(no)]`. |
| `default_ignore` | bool | Everything is ignored unless marked `#[flux_rs::ignore(no)]`. |
| `include` | list of patterns | Check only what matches. |
| `include_trusted` | list of patterns | Trust everything that matches. |
| `include_trusted_impl` | list of patterns | Apply `trusted_impl` to everything that matches. |
| `solver` | `z3` `cvc5` | The SMT solver. |
| `cache` | bool | Reuse solver answers between runs. |
| `allow_uninterpreted_cast` | bool | Accept casts Flux has no meaning for, as unknown values. |
| `dump_constraint` | bool | Write the constraint of each function, for debugging. |

Flags with no metadata key, given through `FLUXFLAGS`:

| Flag | Effect |
|---|---|
| `-Fflux-verbose` | Log each function as it is checked. Names the function when Flux itself crashes. |
| `-Ftimings` | Print the time spent on each function, slowest last. |
| `-Ffixpoint-timeout=<secs>` | Fail a function whose solver query runs longer. |
| `-Fcatch-bugs` | Keep going after an internal error to collect more errors. |
| `-Fpointer-width=32` | Treat `usize` as 32 bits when deciding whether a cast loses bits. |
| `-Fdump-checker-trace`, `-Fdump-fhir`, `-Fdump-rty` | Debugging output for Flux developers. |

The full list is the `Flags` struct in `crates/flux-config/src/flags.rs` of the
Flux repository.

## Include patterns

A pattern selects what `include`, `include_trusted` and `--only-check` apply
to. An item is selected when any pattern matches.

| Pattern | Matches |
|---|---|
| `src/list.rs` or `src/**/*.rs` | every item in files matching the glob |
| `def:name` | items whose path contains `name` |
| `span:src/list.rs:13:1` | the item at that line and column |

```toml
[package.metadata.flux]
enabled = true
# The trusted base is this one file; nothing in it needs its own attribute.
include_trusted = ["src/rvec.rs"]
```

## Editor

For rust-analyzer in VS Code, `.vscode/settings.json`:

```json
{
  "rust-analyzer.check.overrideCommand": [
    "cargo",
    "flux",
    "--workspace",
    "--message-format=json-diagnostic-rendered-ansi"
  ]
}
```
