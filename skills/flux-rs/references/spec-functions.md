# Spec functions

Naming a rule once and using the name in every spec: `defs!`, uninterpreted
functions, `hide` and `reveal`, quantifiers, sort casts, and facts about
operators the solver does not interpret.

```rust
use flux_rs::{assert, attrs::*, defs};
```

## Defining and using

A spec function lives in `defs!` and is written in the refinement language. It
may call other spec functions, bind with `let`, and mention constants. Spec
functions cannot be recursive, directly or through each other.

```rust
defs! {
    fn is_btwn(v: int, lo: int, hi: int) -> bool { lo <= v && v <= hi }
    fn ok_day(d: int) -> bool { is_btwn(d, 1, 31) }
    fn is_month30(m: int) -> bool { m == 4 || m == 6 || m == 9 || m == 11 }
    fn ok_month(d: int, m: int) -> bool { is_btwn(m, 1, 12) && (is_month30(m) => d <= 30) }
    fn double_twice(x: int) -> int {
        let y = x * 2;
        let z = y * 2;
        z
    }
}

#[refined_by(d: int, m: int)]
pub struct Date {
    #[field({usize[d] | ok_day(d)})]
    day: usize,
    #[field({usize[m] | ok_month(d, m)})]
    month: usize,
}

// The Rust function and the spec function say the same thing; the signature
// makes Flux check that they agree.
#[spec(fn(m: usize) -> bool[is_month30(m)])]
fn is_month30(m: usize) -> bool {
    m == 4 || m == 6 || m == 9 || m == 11
}

pub fn date(day: usize, month: usize) -> Option<Date> {
    if 1 <= month && month <= 12 && 1 <= day && day <= 31 && (!is_month30(month) || day <= 30) {
        Some(Date { day, month })
    } else {
        None
    }
}

#[spec(fn() -> i32[double_twice(10)])]
pub fn forty() -> i32 {
    40
}
```

In single-file mode the same block is the crate attribute `#![flux::defs { .. }]`.

## From another crate

A spec function defined in a dependency is used by its full path, or imported
inside `defs!`. The import is scoped to its module, as a Rust `use` is.

```rust
mod imported {
    use flux_rs::attrs::*;

    defs! {
        use flux_core::num::clamp;
    }

    #[spec(fn(x: i32) -> i32[clamp(x, 0, 10)])]
    pub fn to_range(x: i32) -> i32 {
        if x < 0 {
            0
        } else if x > 10 {
            10
        } else {
            x
        }
    }

    #[spec(fn(x: i32{0 <= x && x < 10}) -> i32[flux_core::num::clamp(x, 0, 10)])]
    pub fn already_in_range(x: i32) -> i32 {
        x
    }
}
```

## Uninterpreted functions

A spec function with no body is uninterpreted: Flux knows only that equal
inputs give equal outputs. Use one for a property Flux cannot compute, such as
anything about the contents of a string. The function that establishes the
property is `trusted`; everything downstream is proved from its spec.

```rust
defs! {
    fn valid(x: int) -> bool;
}

#[trusted]
#[spec(fn(x: i32) -> bool[valid(x)])]
fn is_valid(x: i32) -> bool {
    0 <= x && x <= 100
}

#[spec(fn(i32{v: valid(v)}) -> i32)]
fn needs_valid(a: i32) -> i32 {
    a
}

pub fn checked_use(n: i32) {
    if is_valid(n) {
        needs_valid(n);
    }
}
```

## Hiding a definition

A spec function marked `#[hide]` is uninterpreted everywhere except in Rust
functions that `#[reveal]` it. Callers then depend on the rule holding and not
on what it says, so the rule can change without other proofs changing; it also
keeps an expensive definition away from the solver. A Rust function can hide
an otherwise visible definition for itself with `#[hide(name)]`.

```rust
defs! {
    #[hide]
    fn mod33(n: int) -> int { n % 33 }

    #[hide]
    fn lucky(n: int, k: int) -> bool { mod33(n) == k }
}

#[spec(fn(a: i32) requires lucky(a, 7))]
pub fn needs_lucky(_a: i32) {}

#[reveal(lucky, mod33)]
pub fn forty_is_lucky() {
    needs_lucky(40)
}

// With the definition hidden, the property still passes from input to output.
#[spec(fn(xs: &[i32{v: lucky(v, 7)}][100]) -> i32{v: lucky(v, 7)})]
pub fn first_lucky(xs: &[i32]) -> i32 {
    xs[0]
}
```

## Quantifiers

Inside a spec function, `forall` and `exists` range over a literal interval of
integers. A `requires` clause may also quantify over every value with
`forall y. ..`.

```rust
defs! {
    fn marked(i: int, n: int) -> bool;

    fn all_marked(n: int) -> bool {
        forall i in 0..4 { marked(i, n) }
    }

    fn small(n: int) -> bool {
        exists i in 0..4 { i == n }
    }
}

#[trusted]
#[spec(fn(i: i32, n: i32) ensures marked(i, n))]
pub fn mark(_i: i32, _n: i32) {}

#[spec(fn(n: i32) ensures all_marked(n))]
pub fn mark_all(n: i32) {
    mark(0, n);
    mark(1, n);
    mark(2, n);
    mark(3, n);
}

#[spec(fn({i32[@n] | all_marked(n)}) ensures marked(3, n))]
pub fn third_is_marked(_n: i32) {}

#[spec(fn(n: i32) -> bool[small(n)])]
pub fn is_small(n: i32) -> bool {
    n == 0 || n == 1 || n == 2 || n == 3
}

#[spec(fn(x: i32) requires forall y. y >= 0 => y > x)]
pub fn below_every_natural(_x: i32) {}

pub fn minus_one_is() {
    below_every_natural(-1);
}
```

A function with `ensures` and no body worth running is a theorem: Flux proves
it once, and it costs nothing in the program when compiled only under
`#[cfg(flux)]`.

## Casting between sorts

`cast` converts a value of one sort to another, such as a `char` to its code.

```rust
defs! {
    fn is_ascii_digit(c: char) -> bool {
        let i = cast(c);
        48 <= i && i <= 57
    }
    fn digit_value(c: char) -> int { cast(c) - cast('0') }
}

#[spec(fn(c: char{is_ascii_digit(c)}) -> u32[digit_value(c)])]
pub fn value_of(c: char) -> u32 {
    c as u32 - '0' as u32
}
```

## Facts about operators

Flux does not interpret `<<`, `>>`, `&`, `|` or `^` on integers. A `property`
states a fact about one of them, which Flux then uses wherever the operator
appears. Inside the property, `[op](x, y)` is the operator's result.

```rust
defs! {
    property ShiftByTwo[<<](x, y) {
        [<<](x, 2) == 4 * x
    }

    property MaskBy[&](x, y) {
        [&](x, y) <= y
    }
}

#[opts(check_overflow = "none")]
pub fn four() {
    let x: usize = 1 << 2;
    assert(x == 4);
}

static TABLE: [i32; 8] = [0, 1, 2, 3, 4, 5, 6, 7];

pub fn lookup(n: usize) -> i32 {
    TABLE[n & 7]
}
```

A property is taken as given, like a trusted function: state only what is true
of the operator for every input.

## Making an operator unknown

Nonlinear arithmetic can stall the solver even when the proof does not depend
on what the operation computes. `uif_ops` turns the listed operators into
uninterpreted functions: `x * y` still equals `x * y`, and nothing else is
known. It only removes knowledge, so it never makes Flux accept more. Set it
on an item with `opts`, or for the crate with `uif_ops = "*,/"` in
`[package.metadata.flux]`. The operators are `+ - * / % & | ^ << >>`.

```rust
#[opts(uif_ops = "*", check_overflow = "none")]
#[spec(fn(x: i32, y: i32) -> i32[x * y])]
pub fn product(x: i32, y: i32) -> i32 {
    x * y
}

// Without the option `*` is interpreted, so the reordered product is proved.
#[opts(check_overflow = "none")]
#[spec(fn(x: i32, y: i32) -> i32[y * x])]
pub fn product_commutes(x: i32, y: i32) -> i32 {
    x * y
}
```
