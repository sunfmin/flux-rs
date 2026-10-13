# Refinement types and function specs

The forms every spec is built from: types, signatures, references, arrays,
slices, constants, literals, closures and type holes.

Every block is checked by `cargo flux`. The attributes come from
`use flux_rs::attrs::*;`. In single-file mode (`flux file.rs`) write them as
`#[flux::spec(..)]` instead.

## Types

| Form | Meaning |
|---|---|
| `i32[n]` | indexed: the `i32` equal to `n` |
| `i32[@n]` | binds `n` for the rest of the signature |
| `i32{v: v > 0}` | existential: some `i32` that is positive |
| `{i32[@n] \| n < 10}` | constraint on an already-bound parameter |
| `x: i32` | argument syntax, same as `i32[@x]` |
| `x: i32{x > 0}` | argument syntax with a constraint |
| `&Span[@s]` | binds the index of the value behind a reference; `s: &Span` binds nothing usable |
| `&[T][n]`, `Vec<T>[n]`, `[T; N]` | length `n`, or the constant `N` |
| `&[i32{v: v > 0}]` | every element is positive |
| `Option<T>[b]`, `Result<T, E>[b]` | `b` is "is `Some`" / "is `Ok`" |
| `bool[b]` | the bool equal to proposition `b` |
| `char['a']`, `&str["cat"]` | that exact character or string |
| `_` | a hole: take this part from the Rust signature |

`#[spec(..)]` and `#[sig(..)]` are the same attribute, and either may repeat
the function's name: `#[spec(fn five() -> usize[5])]`.

Refinement expressions:

```text
r ::= n | x | x.f                 numbers, variables, index fields
    | r + r | r - r | r * r | r / r | r % r
    | r == r | r != r | r < r | r <= r | r > r | r >= r
    | r && r | r || r | !r | r => r
    | if r { r } else { r }
    | f(r, ..)                    spec functions
    | S { f: r, ..r }             a struct index, built or updated
```

Sorts are `int`, `bool`, `real`, `char`, `str`, `bitvec<N>`, `Set<T>`,
`Map<K, V>`, and any reflected enum or `refined_by` type.

## Functions

A precondition sits on its argument or in a `requires` clause; the two are the
same. `flux_rs::assert` is a function requiring `bool[true]`: Flux proves the
condition where the standard macro would test it.

```rust
use flux_rs::{assert, attrs::*};

#[spec(fn(x: i32{x < 100}) -> i32{v: v > x})]
pub fn inc(x: i32) -> i32 {
    x + 1
}

#[spec(fn(a: u32, b: u32) -> u32[a + b] requires a + b <= u32::MAX)]
pub fn add(a: u32, b: u32) -> u32 {
    a + b
}

#[spec(fn five() -> usize[5])]
pub fn five() -> usize {
    let x = 2;
    let y = 3;
    assert(x + y == 5);
    x + y
}
```

## References

`&T` and `&mut T` carry the type as an invariant: the callee may read or write,
and the refinement holds before and after. To say a call *changes* the
refinement, add `ensures`, after any `requires`. Read through a `&mut` once into a local: Flux forgets
what a test of `*p` showed by the time `*p` is read again.

```rust
#[spec(fn(p: &mut i32{v: 0 <= v}))]
pub fn bump(p: &mut i32) {
    let v = *p;
    if v < 100 {
        *p = v + 1;
    }
}

#[spec(fn(v: &mut Vec<i32>[@n]) ensures v: Vec<i32>[n + 1])]
pub fn push_one(v: &mut Vec<i32>) {
    v.push(1);
}

#[spec(fn(x: &mut i32[@n]) ensures x: i32[0])]
pub fn reset(x: &mut i32) {
    *x = 0;
}

// A caller holding only an invariant may still call a function that changes
// the refinement, when the result keeps the invariant.
#[spec(fn(z: &mut i32{v: 0 <= v}))]
pub fn reset_under_invariant(z: &mut i32) {
    reset(z);
}
```

Older code writes the changing form as `x: &strg i32[@n]`; it means the same.

## Arrays and slices

An array's length is its Rust length, so indexing by a constant is checked with
nothing written. A slice carries its length as an index.

```rust
const BUFLEN: usize = 100;

#[spec(fn() -> [i32{v: v >= 0}; 2])]
pub fn pair() -> [i32; 2] {
    [0, 1]
}

pub fn last(buf: &[i32; BUFLEN]) -> i32 {
    buf[BUFLEN - 1]
}

#[spec(fn(xs: &[i32]{n: n > 0}) -> i32)]
pub fn head(xs: &[i32]) -> i32 {
    xs[0]
}

#[spec(fn(&[i32{v: v > 0}]) -> Option<&i32{v: v >= 0}>)]
pub fn first(xs: &[i32]) -> Option<&i32> {
    xs.first()
}

#[spec(fn(x: &mut [i32][@n], y: &[i32][n]))]
pub fn copy_into(x: &mut [i32], y: &[i32]) {
    let mut i = 0;
    while i < x.len() {
        x[i] = y[i];
        i += 1;
    }
}
```

## Constants and const generics

Integer constants, associated constants and const generic parameters are usable
by name inside a refinement.

```rust
pub struct Cow;

impl Cow {
    const GRASS: usize = 12;

    #[spec(fn() -> usize[12])]
    pub fn grass() -> usize {
        Self::GRASS
    }
}

#[spec(fn(x: usize{x < BUFLEN}) -> usize{v: v <= BUFLEN})]
pub fn next_slot(x: usize) -> usize {
    x + 1
}

#[invariant(N > 0)]
pub struct Ring<const N: usize> {
    at: usize,
}

#[spec(fn(x: usize, _) -> usize{v: v < N})]
pub fn wrap<const N: usize>(x: usize, _ring: &Ring<N>) -> usize {
    x % N
}
```

## Characters and strings

```rust
#[spec(fn() -> char['a'])]
pub fn letter_a() -> char {
    'a'
}

#[spec(fn(c: char{'a' <= c && c <= 'z'}) -> char[c])]
pub fn lowercase(c: char) -> char {
    c
}

#[spec(fn(&str["cat"]))]
pub fn require_cat(_x: &str) {}

pub fn give_cat() {
    require_cat("cat");
}
```

## Closures and function pointers

A closure is checked where it is written, against the refinements of what it
captures. A named function passed as a value keeps its spec. To constrain what
a caller's closure receives, refine the bound in a `where` clause.

```rust
#[spec(fn(Option<i32{v: 0 <= v && v < 100}>) -> Option<i32{v: 3 <= v}>)]
pub fn add_three(x: Option<i32>) -> Option<i32> {
    let y = 1;
    let z = 2;
    x.map(|x| x + y + z)
}

#[spec(fn(x: usize{x < 100}) -> usize[x + 1])]
fn succ(x: usize) -> usize {
    x + 1
}

#[spec(fn(Option<usize[9]>) -> Option<usize[10]>)]
pub fn ten(c: Option<usize>) -> Option<usize> {
    c.map(succ)
}

#[spec(fn(n: usize, visit: F) where F: FnMut(usize{i: i < n}))]
pub fn each_index<F>(n: usize, mut visit: F)
where
    F: FnMut(usize),
{
    let mut i = 0;
    while i < n {
        visit(i);
        i += 1;
    }
}
```

## Type holes

`_` stands for whatever the Rust signature says, so a spec names only the part
it is about. It works in signatures, fields, variants, aliases and generic
arguments. A spec made only of holes says nothing; leave it off.

```rust
// Only the claim is written: the result is always `Some`.
#[spec(fn(_) -> Option<_>[true])]
pub fn wrap_some(x: i32) -> Option<i32> {
    Some(x)
}

#[spec(fn(x: &mut _) ensures x: i32[0])]
pub fn zero(x: &mut i32) {
    *x = 0;
}

#[refined_by()]
pub struct Loaded {
    #[field(Option<_>[true])]
    x: Option<i32>,
}

#[alias(type NonEmpty = Vec<_>{n: n > 0})]
pub type NonEmpty = Vec<i32>;

#[spec(fn(NonEmpty) -> i32)]
pub fn first_of(v: NonEmpty) -> i32 {
    v[0]
}
```
