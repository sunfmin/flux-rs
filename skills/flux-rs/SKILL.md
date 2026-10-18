---
name: flux-rs
description: Flux, the refinement type checker for Rust (flux-rs, liquid types, `cargo flux`) — write and repair the specs that prove at compile time a Rust index is in bounds, arithmetic cannot overflow, an unwrap cannot panic, or a state changes only as allowed. Use when adding Flux to a Rust crate, writing or changing a `#[spec]`, `#[sig]`, `#[refined_by]`, `#[invariant]` or `extern_spec`, fixing a `cargo flux` error such as "refinement type error" or "a precondition cannot be proved", deciding what may be `trusted`, or when a project requires a crate to pass Flux. Not the FLUX image models, Flux CD for Kubernetes, or the Flux state pattern in JavaScript.
---

# Flux

Flux reads refinements written as attributes on ordinary Rust and proves them
with an SMT solver while compiling. A refinement is a rule about a value's
number: this index is below that length, this count never passes that total. A
plain `cargo build` on stable ignores every attribute, so Flux is a second
compiler pass, with no cost at run time.

## Reference

Every Flux feature has a checked example in one of these files. Read
`types.md` before the first spec of a session, and the others when the task
reaches them.

| File | Read it for |
|---|---|
| [`references/types.md`](references/types.md) | indexed, existential and constraint types; `requires` and `ensures`; `&mut`; arrays, slices, constants, const generics; `char` and `str`; closures and function pointers; type holes |
| [`references/data.md`](references/data.md) | `refined_by`, `field`, `invariant`; record syntax for indexes; `opaque` structs with a trusted API; `reflect` and refined enum variants; typestate; type aliases |
| [`references/spec-functions.md`](references/spec-functions.md) | `defs!`, `let`, importing from another crate; uninterpreted functions; `hide` and `reveal`; `forall` and `exists`; `cast`; `property` for `<<` `&` and the like; `uif_ops` |
| [`references/traits.md`](references/traits.md) | specs on trait methods and what an impl may change; associated refinements; refined associated types; `impl Trait`; `dyn Trait`; generic refinements (`hrn`) |
| [`references/sets-bitvectors.md`](references/sets-bitvectors.md) | `Set<T>` and `Map<K, V>` indexes; `BV32` and `bitvec<N>`; bitvector constants and widening |
| [`references/externs.md`](references/externs.md) | what `Option`, `Result`, `Vec`, slices, ranges and iterators already promise; `extern_spec` for a function, struct, primitive, enum, trait; detached `specs` for derived or untouched code |
| [`references/proving.md`](references/proving.md) | loops: `scrape_quals`, `invariant!`, `qualifier!`; `trusted`, `ignore`, `trusted_derive`; overflow modes; `no_panic`; `should_fail` |
| [`references/running.md`](references/running.md) | `cargo flux` and `flux` commands; every option and the four places to set one; include patterns; editor setup |

## Set up a crate

Flux is installed when `cargo flux --version`, `fixpoint --version` and
`z3 --version` all answer. If one is missing, follow the
[install guide](https://flux-rs.github.io/flux/guide/install.html); it builds
Flux from source, so ask the user before starting.

```toml
[dependencies]
# Refinement attributes; they expand to nothing under a plain `cargo build`.
flux-rs = { git = "https://github.com/flux-rs/flux.git", rev = "b2f3e31e17727ffe08c2efee1e7aa0bc4f0a66f9" }
# Refinement specs for core and alloc (Option, Vec, slices, ...).
flux-core = { git = "https://github.com/flux-rs/flux.git", rev = "b2f3e31e17727ffe08c2efee1e7aa0bc4f0a66f9" }
flux-alloc = { git = "https://github.com/flux-rs/flux.git", rev = "b2f3e31e17727ffe08c2efee1e7aa0bc4f0a66f9" }

[package.metadata.flux]
enabled = true
check_overflow = "strict"

[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(flux)'] }
```

- **Pin `rev` to the installed checker.** `cargo flux --version` prints its
  commit; the three crates take the full hash of that commit. Flux has no
  releases, and a spec crate from another commit fails in ways that look like
  your bug.
- **Link the spec crates** at the crate root, or `Vec` and `Option` have no
  refinements and specs about them fail with `mismatched sorts`:
  ```rust
  extern crate flux_alloc;
  extern crate flux_core;
  ```
- **Run it through rustup's cargo.** `cargo flux` re-invokes `cargo +<nightly>`,
  which a cargo installed outside rustup rejects. Put the invocation in a
  `verify.sh` that sets it up once:
  ```sh
  PATH="$HOME/.cargo/bin:$PATH"
  : "${RUSTUP_TOOLCHAIN:=$(rustup toolchain list | head -1 | cut -d' ' -f1)}"
  export PATH RUSTUP_TOOLCHAIN
  exec cargo flux "$@"
  ```

Checking is fast enough to run after every edit: about 150 functions take 2
seconds once the dependencies are built.

**In a gate**, run Flux alone, before the tests, with a limit on each solver
query and none on the whole run:

```sh
FLUXFLAGS="-Ftimings -Ffixpoint-timeout=20 -Fcatch-bugs" ./verify.sh
```

- Alone and first: run beside the tests it shares the cores with every one of
  them, and how long it took says more of them than of it.
- `-Ffixpoint-timeout=20` stops any one query past twenty seconds and fails
  with `fixpoint query timed out` on the function, by name. A function's query
  can otherwise run for many minutes, and nothing says which. Limit the whole
  run instead and a run cut short names nothing: Flux prints its timings only
  once it ends.
- `-Fcatch-bugs` checks on past an error, so one run names every slow function
  and still ends with `-Ftimings`' report of the slowest.

## The loop

1. **Say the rule in one sentence**, with its "for every": *for every stack and
   every index handed to `get`, the index is below the length.* A rule you
   cannot say this way is behavior; write a test for it instead.
2. **Put the rule on the type that owns the number.** A fact about one value is
   an index or invariant on its type (`Stack[n]`, `#[invariant(lo <= hi)]`).
   A fact about a call is a precondition on the argument. A rule used in two
   specs gets a name in `defs!`.
3. **Run `cargo flux`** and read the first error. Each one ends with the command
   that rechecks only that function.
4. **Fix the side that is wrong.** The error means a caller, a body or a spec
   disagrees with the rule from step 1. Change whichever one does. When the
   body is right and Flux lacks a fact, supply the fact (see *Reading an
   error*).
5. **Write the misuse.** Add a `#[should_fail]` function, in a `#[cfg(flux)]`
   module, that breaks the rule the way a careless caller would. It turns the
   spec into something that can go red: weaken the spec later and this fails.
   `should_fail` passes on any error, so remove the attribute once and see the
   error land on the line you meant, then put it back.
6. **Audit every spec you wrote** against the next section.
7. **Read the summary line.**
   `summary. 151 functions processed: 132 checked; 18 trusted; 1 ignored.`
   Each dependency prints its own; the crate's is the last. The warning about
   `custom_inner_attributes` is Flux's own and always there.

Done means `cargo flux` exits 0, `cargo build` and `cargo test` still pass on
stable, every spec passed the audit, and the trusted and ignored counts are
what they were before, or each addition is named to the user with its reason.

## Every spec must earn its place

A spec that repeats the Rust signature proves nothing: Flux checks the body
the same with or without it.

```rust
#[spec(fn(v: &Vec<i32>, i: usize) -> Option<i32>)]         // says nothing
#[spec(fn(&Vec<i32>[@n], i: usize) -> Option<i32>[i < n])] // Some exactly when i is inside
```

For each `spec`, `field`, `variant`, `invariant` and `alias`, name the wrong
program it rejects: a caller it stops, or a body it would refuse. Then act on
the answer.

| What you find | Do |
|---|---|
| It rejects a program, and a `should_fail` shows it | Keep it. |
| It rejects a program you can describe, with no `should_fail` yet | Write the `should_fail`. |
| It names an index with `@n` or `x:` and never uses it | The binding is noise. Use it in the result or a condition, or drop it. |
| It is the Rust signature again, or made only of `_` | Delete it. The body is still checked. |
| The result is unrefined though the body computes something exact | Say what it returns (`-> usize[n + 1]`), so callers can rely on it. |
| The precondition is stronger than the body needs | Loosen it to what the body needs; every caller pays for the excess. |

The same test applies to a `trusted` function's spec, more strictly: it is a
claim nobody checks, so it must be both useful and plainly true of the body.

## Reading an error

| Flux says | It means | Usual fix |
|---|---|---|
| `refinement type error` … `a precondition cannot be proved` | The call site cannot show what the callee requires. The note points at the exact condition. | Check before the call (`if i < v.len()`), or require it of your own caller. |
| … `a postcondition cannot be proved` | The body does not return what the spec promises. | Fix the body, or the promise. |
| the same, pointing into `flux-core` at `in_bounds` or `Option<T>[true]` | `v[i]`, `.unwrap()` or `.expect()` on a value Flux has no fact about. | Branch on `len()` / `is_some()`, `match`, or carry the fact in the argument's type. |
| `arithmetic operation may overflow` | Under `check_overflow = "strict"`, nothing bounds the operands. | Bound the inputs in the spec, or use `checked_*` and handle `None`. |
| `assertion might fail: possible division by zero` | The divisor has no `> 0` fact. | Require it or test it. |
| `assignment might be unsafe` | A write through `&mut T{..}` may break the refinement on `T`. | Guard the write, or use `ensures` if the refinement is meant to change. |
| `type invariant may not hold (when place is folded)` | After a call that changed what a `&mut` holds, the value no longer fits the reference's refinement. | Establish the bound in a local before the call, or weaken the reference's refinement. |
| `call to … may panic` | A `no_panic` function calls something not known to be panic-free. | Remove the call, give the callee a `no_panic` extern spec, or drop `no_panic`. |
| `mismatched sorts` on `Vec<T>[n]` | The spec crates are not linked. | `extern crate flux_alloc; extern crate flux_core;` |
| `parameter … refers to a type with no indices` | `s: &Span` names the reference. | Bind the value: `&Span[@s]`. |
| `syntax error` at `requires` | `requires` was written after `ensures`. | Order is result, `requires`, `ensures`. |
| `invalid extern spec` … `generic parameters don't match` | The stub differs from the real signature. | Copy the external signature exactly, generics and names included. |
| `cannot access fields of opaque struct` | Only trusted code may look inside an `opaque` struct. | Go through its API, or add a trusted function to it. |
| `fixpoint query timed out` | One function's constraint is too big for the solver in the time given: usually a loop whose body has many branches, solved with the loop's invariant as one query. | Move the body of one turn into its own function, its spec saying what one turn keeps (`-> Slots{a: a.held <= s.held}`), and leave the loop only the invariant. One such function went from past 20 s to 3 s. |
| An internal compiler error | A Flux bug. | `FLUXFLAGS="-Fflux-verbose" cargo flux` names the function; mark it `trusted(reason = "..")` and tell the user. |

When the code is right and the proof still fails, Flux is missing a fact:

- **A loop** forgets how its variables relate. State it at the top of the body:
  `invariant!(res: int; res + i == n)`. When the fact has the same shape as
  something in the function's spec, `#[opts(scrape_quals = "true")]` on the
  function finds it with nothing written.
- **A `&mut` read twice** loses what the first read showed. Read once into a
  local, test and write from the local.
- **`*`, `/`, `%` between two variables** is nonlinear and the solver may give
  up. Bound each operand, or restate the rule without the product. A result
  that repeats the body's own expression (`-> u32[total / count]`) is fine.
- **`<<`, `>>`, `&`, `|`, `^` on integers** mean nothing to Flux until a
  `property` states the fact you need, or the value is a `BV32`.
- **A std function** returns an unrefined value. Give it an `extern_spec`.
- **A callee's result is unrefined.** A spec that promises only `v >= 0` lets
  the caller know nothing more. Strengthen the callee's result.

## What is trusted

`trusted`, `extern_spec`, `property`, `opaque` APIs and uninterpreted spec
functions are claims made by hand. Every proof rests on them, and Flux never
checks them.

- Keep the trusted base in one place: one small file per opaque type, named
  once with `include_trusted = ["src/rvec.rs"]` in `[package.metadata.flux]`.
- A trusted function is a few lines whose spec can be read off its body.
- Reaching for `trusted` or `ignore` to get past an error is a decision for the
  user: stop and show them the error and the claim you would be making.
- Where a project sets a bar for the counts, such as `0 trusted; 0 ignored` for
  a crate, that bar is the completion criterion.

## What Flux leaves unproved

- **That a call happens.** Flux proves what a call requires. To force a step,
  make it the only way to build the value the next step takes.
- **Behavior.** That the second item is the one marked done is a test's job.
- **The world.** A proof starts from the types at the crate's edge. Parse
  untrusted input through one function whose return type carries the fact
  (`fn(&Stack[@n], pos: usize) -> Option<usize{i: i < n}>`), and make that the
  only source of such values.

## Keeping this skill true

The `rev` above is the one place the Flux revision is written. After changing
it, or any block in a reference, run `scripts/check_reference.sh`: it runs
Flux and a stable build over every Rust block of `references/`.
