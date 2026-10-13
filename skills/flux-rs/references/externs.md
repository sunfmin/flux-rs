# Specs for code you do not own, and specs kept apart from the code

What the standard library already promises, how to add a promise for an
external function, type, impl or trait, and how to state a spec away from the
item it describes.

```rust
use flux_rs::{assert, attrs::*, defs};
```

## What std already has

`flux-core` and `flux-alloc` give refinements to the standard library once
they are linked with `extern crate`. Read their source, in the Flux repository
under `lib/`, to see exactly what a function promises.

| Type | Index | Refined operations include |
|---|---|---|
| `Option<T>` | `bool`, is `Some` | `is_some`, `is_none`, `unwrap`, `expect`, `map`, `and_then`, `ok_or`, `take`, `?` |
| `Result<T, E>` | `bool`, is `Ok` | `is_ok`, `is_err`, `ok`, `err`, `map`, `map_err`, `unwrap`, `expect`, `?` |
| `[T]`, `&[T]` | `int`, the length | `len`, `is_empty`, indexing, `get`, `first`, `last`, `split_at`, `split_first`, `iter`, `windows`, `to_vec` |
| `Vec<T>` | `int`, the length | `new`, `push`, `pop`, `len`, `is_empty`, indexing, `clone`, deref to a slice |
| `String` | `int`, the length | `==`, `clone` |
| `Range<A>` | `start`, `end` | `next`, and so `for i in a..b`, for `usize` and `i32` |
| iterators | position and length | `next`, `enumerate`, `into_iter` on a `&Vec` |

```rust
// No spec: the body is still checked, and `unwrap` is proved safe by the test.
pub fn or_zero(o: Option<i32>) -> i32 {
    if o.is_some() { o.unwrap() } else { 0 }
}

// The answer is `Some` exactly when the index is inside the vector.
#[spec(fn(&Vec<i32>[@n], i: usize) -> Option<i32>[i < n])]
pub fn get(v: &Vec<i32>, i: usize) -> Option<i32> {
    if i < v.len() { Some(v[i]) } else { None }
}

// So a caller with an index it knows is inside may unwrap.
#[spec(fn(v: &Vec<i32>{n: n > 0}) -> i32)]
pub fn first(v: &Vec<i32>) -> i32 {
    get(v, 0).unwrap()
}

pub fn pop_after_push() -> i32 {
    let mut v = Vec::new();
    v.push(1);
    v.pop().unwrap()
}

// No spec is needed for these two: the specs of ranges and iterators already
// say the loop variable is inside.
pub fn range_stays_inside(n: i32) {
    for i in 0..n {
        assert(0 <= i);
        assert(i < n);
    }
}

pub fn enumerate_stays_inside(xs: &[usize]) {
    for (i, _) in xs.iter().enumerate() {
        assert(i < xs.len())
    }
}
```

## Extern specs

`extern_spec` gives a spec to an item from another crate. Flux cannot see the
body, so every extern spec is trusted: it only checks that the stub's types
match. The attribute's argument is the module the item lives in. The stub must
repeat the external signature exactly, generic parameters and their names
included.

### A function

```rust
#[extern_spec(std::mem)]
#[spec(fn(x: &mut T[@vx], y: &mut T[@vy]) ensures x: T[vy], y: T[vx])]
fn swap<T>(a: &mut T, b: &mut T);

pub fn swapped() {
    let mut x = 5;
    let mut y = 10;
    std::mem::swap(&mut x, &mut y);
    assert(x == 10);
    assert(y == 5);
}
```

### A struct and its methods

An extern struct is declared with `refined_by` and no fields, and behaves as
an opaque type. Its methods go in an `impl` stub; only the ones you list get a
spec.

```rust
use std::time::Duration;

#[extern_spec(std::time)]
#[refined_by(secs: int)]
struct Duration;

#[extern_spec(std::time)]
impl Duration {
    #[spec(fn(secs: u64) -> Duration[secs])]
    const fn from_secs(secs: u64) -> Duration;

    #[spec(fn(&Duration[@d]) -> u64[d])]
    const fn as_secs(&self) -> u64;
}

pub fn round_trip() {
    let d = Duration::from_secs(3);
    assert(d.as_secs() == 3);
}
```

A struct with public fields can list them, each tied to an index, as
`flux-core` does for `Range`:

```text
#[extern_spec(std::ops)]
#[refined_by(start: Idx, end: Idx)]
struct Range<Idx> {
    #[field(Idx[start])]
    start: Idx,
    #[field(Idx[end])]
    end: Idx,
}
```

### A primitive type

```rust
defs! {
    fn is_ascii_digit(c: char) -> bool {
        let i = cast(c);
        48 <= i && i <= 57
    }
}

#[extern_spec]
impl char {
    #[spec(fn(&char[@c]) -> bool[is_ascii_digit(c)])]
    const fn is_ascii_digit(&self) -> bool;
}

#[spec(fn(c: char{'0' <= c && c <= '9'}))]
pub fn digit_is_digit(c: char) {
    assert(c.is_ascii_digit())
}
```

### An enum

An extern enum repeats its variants, each with a `variant` spec. `Option` in
`flux-core` is written this way:

```text
#[extern_spec]
#[refined_by(is_some: bool)]
enum Option<T> {
    #[variant(Option<T>[false])]
    None,
    #[variant((T) -> Option<T>[true])]
    Some(T),
}
```

### A trait

An extern trait can declare associated refinements, with a default, and say
what its methods return in terms of them. An impl then defines them for its
type.

```rust
#[extern_spec(std::default)]
#[reft(fn is_default(value: Self) -> bool { true })]
trait Default {
    #[spec(fn() -> Self{value: <Self as Default>::is_default(value)})]
    fn default() -> Self;
}

#[refined_by(n: int)]
pub struct Level {
    #[field(u8[n])]
    n: u8,
}

#[reft(fn is_default(value: Level) -> bool { value.n == 1 })]
impl Default for Level {
    #[spec(fn() -> Level[1])]
    fn default() -> Level {
        Level { n: 1 }
    }
}

#[spec(fn() -> Level[1])]
pub fn starting_level() -> Level {
    Level::default()
}
```

An impl of an external trait for an external type is given the same way:
`#[extern_spec] impl<T> TheTrait for Vec<T> { .. }`.

## Detached specs

A spec can be written apart from its item: for code a derive or macro writes,
or to keep a source file untouched. Put the specs in a `specs` block on a
`const _: () = ();` in the same module, or use the `detached_spec!` macro,
which expands to that. Inside the block the signatures are bare, with no
`#[spec]` around them.

### Functions, structs and enums

```rust
pub fn double(x: u8) -> u16 {
    x as u16 * 2
}

pub struct Ordered {
    x: usize,
    y: usize,
}

pub fn ordered(x: usize, y: usize) -> Ordered {
    if x < y { Ordered { x, y } } else { Ordered { x: y, y: x } }
}

pub enum Nat {
    Zero,
    Succ(Box<Nat>),
}

pub fn two() -> Nat {
    Nat::Succ(Box::new(Nat::Succ(Box::new(Nat::Zero))))
}

#[specs {
    fn double(x: u8) -> u16[x * 2];

    #[refined_by(vx: int, vy: int)]
    #[invariant(vx <= vy)]
    struct Ordered {
        x: usize[vx],
        y: usize[vy],
    }

    #[refined_by(n: int)]
    #[invariant(0 <= n)]
    enum Nat {
        Zero               -> Nat[0],
        Succ(Box<Nat[@n]>) -> Nat[n + 1],
    }

    fn two() -> Nat[2];
}]
const _: () = ();
```

### Impls and traits

Methods are grouped under an `impl` that mirrors the real one. A trait's
associated refinement is marked `#[reft]`.

```rust
pub struct Counter {
    n: usize,
}

impl Counter {
    pub fn zero() -> Counter {
        Counter { n: 0 }
    }
}

pub trait Weigh {
    fn weight(&self) -> usize;
}

pub struct Feather;

impl Weigh for Feather {
    fn weight(&self) -> usize {
        1
    }
}

#[specs {
    #[refined_by(n: int)]
    struct Counter {
        n: usize[n],
    }

    impl Counter {
        fn zero() -> Counter[0];
    }

    trait Weigh {
        #[reft]
        fn heavy(x: int) -> bool;

        fn weight(&Self) -> usize{v: !Self::heavy(v)};
    }

    impl Weigh for Feather {
        #[reft]
        fn heavy(x: int) -> bool { x > 100 }

        fn weight(&Self) -> usize[1];
    }
}]
const _: () = ();

#[spec(fn(Feather) -> usize[1])]
pub fn feather_weight(f: Feather) -> usize {
    f.weight()
}
```

### A derived impl

A derive writes a function with no place for a spec. Name the trait by its
full path and give the method's spec; pair it with `trusted_derive` when Flux
cannot check the derived body.

```rust
#[reflect]
#[derive(Clone, Copy, PartialEq)]
#[trusted_derive(reason = "the derived comparison is not checkable")]
pub enum Door {
    Open,
    Shut,
}

#[specs {
    impl std::cmp::PartialEq for Door {
        fn eq(&Door[@a], &Door[@b]) -> bool[a == b];
    }
}]
const _: () = ();

#[spec(fn(d: Door) -> bool[d == Door::Open])]
pub fn is_open(d: Door) -> bool {
    d == Door::Open
}
```

A spec for an item in a nested module is written inside matching `mod` blocks:
`mod x { mod y { impl a::b::MyTrait for Thing<T> { .. } } }`.
