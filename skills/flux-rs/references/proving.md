# Loops, trust and checks

Giving the solver a missing fact, and the attributes that decide what is
checked, what is assumed, and what must be rejected.

```rust
use flux_rs::{assert, attrs::*, macros::{invariant, qualifier}};
```

## Loops

Flux infers a loop's invariant from templates called qualifiers: shapes such as
`a <= b` or `a == b + c` over the variables in scope. Most loops need nothing
written.

```rust
#[spec(fn(n: usize) -> usize[n])]
pub fn count_up(n: usize) -> usize {
    let mut i = 0;
    while i < n {
        i += 1;
    }
    i
}

#[spec(fn(k: i32{0 <= k}) -> i32[0])]
pub fn drain(mut k: i32) -> i32 {
    while k > 0 {
        k -= 1;
    }
    k
}
```

When a loop fails, the invariant has a shape Flux did not try. Three ways to
supply it, from least to most written:

**Scrape.** `scrape_quals` lets Flux try every shape that appears in the
function's own specs. It finds an invariant that looks like the postcondition.

```rust
#[opts(scrape_quals = "true")]
#[spec(fn(lo: usize, hi: usize{lo <= hi}) -> Vec<usize>[hi - lo])]
pub fn range(lo: usize, hi: usize) -> Vec<usize> {
    let mut i = lo;
    let mut res = Vec::new();
    while i < hi {
        res.push(i);
        i += 1;
    }
    res
}
```

**`invariant!`** states the fact at the top of the loop body. It asserts the
fact and offers its shape to the solver. Variables that are not plain integers
in scope are declared before the `;`.

```rust
#[spec(fn(n: usize) -> usize[n])]
pub fn count_down(n: usize) -> usize {
    let mut i = n;
    let mut res = 0;
    while i > 0 {
        invariant!(res: int; res + i == n);
        i -= 1;
        res += 1;
    }
    res
}
```

**`qualifier!`** only offers the shape, leaving any assertion to you. Its body
is never compiled as Rust, so it can use spec functions and `=>`.

```rust
#[spec(fn(n: usize) -> usize[n])]
pub fn count_down_again(n: usize) -> usize {
    let mut i = n;
    let mut res = 0;
    while i > 0 {
        qualifier!(res: int; i >= 0 => res + i == n);
        assert(res + i == n);
        i -= 1;
        res += 1;
    }
    res
}
```

A qualifier for a whole crate or module is declared in `defs!`:
`qualifier Sub2(x: int, a: int, b: int) { x == a - b }`.

## Trusted and ignored code

| Attribute | Effect |
|---|---|
| `#[trusted]` | The spec is taken as given and the body is not checked. Checked code may call it. |
| `#[trusted(reason = "..")]` | The same, with the reason recorded. |
| `#[trusted_impl]` | On a trait method: the spec is not compared with the trait's. |
| `#[flux_rs::ignore]` | Flux does not look at the item. Written in full, since `#[ignore]` is Rust's own. Only trusted or ignored code may call it. |
| `#[trusted_derive]` | Skip the bodies `#[derive]` writes for this one type. Opaque types have it implicitly. Not inherited by nested items. |

`trusted` and `ignore` apply to everything nested inside the item, and `(no)`
turns them back off. To adopt Flux one module at a time, ignore the crate with
`#![flux_rs::ignore]` and opt modules in with `#[flux_rs::ignore(no)]`. The
metadata keys `default_trusted` and `default_ignore` do the same for a crate,
and `include_trusted = ["src/file.rs"]` trusts everything in one file.

```rust
#[trusted(reason = "the allocator call is outside what Flux models")]
#[spec(fn(n: usize) -> Vec<u8>[n])]
pub fn zeroed(n: usize) -> Vec<u8> {
    vec![0; n]
}

#[flux_rs::ignore]
pub mod legacy {
    pub fn unchecked(v: &Vec<i32>) -> i32 {
        v[0]
    }

    #[flux_rs::ignore(no)]
    pub mod adopted {
        pub fn checked(v: &Vec<i32>) -> i32 {
            if v.len() > 0 { v[0] } else { 0 }
        }
    }
}

#[derive(Debug, Hash)]
#[trusted_derive]
#[flux_rs::refined_by(n: int)]
pub struct Id(#[field(u32[n])] u32);
```

The summary line counts trusted and ignored functions, so an addition shows.

## Overflow

`check_overflow` has three modes. `none`, the default, still checks that an
unsigned subtraction cannot go below zero. `lazy` checks underflow and forgets
the value of anything that might overflow. `strict` requires proof that no
arithmetic operation overflows or underflows. Set it for the crate in
`[package.metadata.flux]`, or for one item, impl, trait or module with `opts`.

```rust
#[opts(check_overflow = "strict")]
#[spec(fn(x: u32, y: u32, z: u32) -> u32[x + y + z] requires x + y + z <= u32::MAX)]
pub fn add_three(x: u32, y: u32, z: u32) -> u32 {
    x + y + z
}

#[opts(check_overflow = "none")]
pub fn unchecked_sum(x: u32, y: u32) -> u32 {
    x + y
}
```

Division and remainder always require a divisor Flux can prove is not zero.

## `no_panic`

A function marked `no_panic` may call only code Flux can show is panic-free:
your own functions, whose bodies it examines, and external ones whose extern
spec says `no_panic`. Anything else is rejected with `call to .. may panic`;
`Vec::push` is one, since allocation can fail. Combined with refinement
checking, which already rules out failed indexing and `unwrap`, this proves the
function cannot panic. The metadata key `no_panic = true` applies it to every
function of the crate.

```rust
#[no_panic]
pub fn value_or(o: Option<i32>, fallback: i32) -> i32 {
    o.unwrap_or(fallback)
}
```

## `should_fail`

`should_fail` inverts the check: verification fails if Flux accepts the
function. Write one for each misuse a spec is meant to stop, so a spec that is
later weakened is noticed. Keep them, with any theorems, in one module that is
compiled only under Flux.

```rust
#[spec(fn(lo: i32, hi: i32{lo <= hi}) -> i32[hi - lo] requires hi - lo <= i32::MAX)]
pub fn width(lo: i32, hi: i32) -> i32 {
    hi - lo
}

#[cfg(flux)]
#[allow(dead_code)]
mod rejected {
    use super::*;

    #[should_fail]
    fn width_of_backwards_span() -> i32 {
        width(5, 1)
    }

    // A theorem: checked once by Flux, never run.
    #[spec(fn(lo: i32, mid: i32{lo <= mid}, hi: i32{mid <= hi}) requires hi - lo <= 1000)]
    fn widths_add_up(lo: i32, mid: i32, hi: i32) {
        assert(width(lo, mid) + width(mid, hi) == width(lo, hi))
    }
}
```

`should_fail` passes on any error, so keep each misuse to the one line that
breaks the rule.
