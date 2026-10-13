# Refined structs, enums and aliases

How a type carries its own rule: indexes, invariants, opaque types with a
trusted API, refined enums, and type aliases.

```rust
use flux_rs::{assert, attrs::*};
```

## Structs

`refined_by` declares the indexes, `field` ties each field to them, and
`invariant` states what always holds between them. Building the struct must
prove the invariant; holding one gives it for free.

```rust
#[refined_by(lo: int, hi: int)]
#[invariant(lo <= hi)]
pub struct Span {
    #[field(i32[lo])]
    pub lo: i32,
    #[field(i32[hi])]
    pub hi: i32,
}

#[spec(fn(lo: i32, hi: i32{lo <= hi}) -> Span[lo, hi])]
pub fn span(lo: i32, hi: i32) -> Span {
    Span { lo, hi }
}

#[spec(fn(&Span[@s]) -> i32{v: v >= 0} requires s.hi - s.lo <= i32::MAX)]
pub fn width(s: &Span) -> i32 {
    s.hi - s.lo
}
```

A field may carry its own constraint without the struct having an index:

```rust
#[refined_by()]
pub struct Positive {
    #[field(i32{v: v > 0})]
    pub n: i32,
}

#[refined_by(n: int)]
pub struct Meters(#[field(i32[n])] pub i32);
```

## Naming indexes by field

A struct's index can be written positionally (`Span[lo, hi]`) or as a record,
and updated like one. Record syntax keeps a spec true when an index is added.

```rust
#[refined_by(x: int, y: int)]
pub struct Point {
    #[field(u32[x])]
    x: u32,
    #[field(u32[y])]
    y: u32,
}

#[spec(fn(Point) -> Point[Point { x: 1, y: 2 }])]
pub fn at_one_two(mut p: Point) -> Point {
    p.x = 1;
    p.y = 2;
    p
}

impl Point {
    #[spec(fn(self: &mut Point[@old]) ensures self: Point[Point { x: 1, ..old }])]
    pub fn move_to_one(&mut self) {
        self.x = 1;
    }

    // The type's name may be left out when it is clear from the context.
    #[spec(fn(self: &mut Point[@old]) ensures self: Point[{ y: 0, ..old }])]
    pub fn drop_to_floor(&mut self) {
        self.y = 0;
    }
}

#[spec(fn(p: Point{v: v == Point { x: 0, y: 0 }}))]
pub fn needs_origin(_p: Point) {}
```

## Opaque structs

When the index is not a field (a length, a set of members), make the struct
`opaque` and give it a small API of `trusted` functions. Fields of an opaque
struct are readable only in trusted code, and cannot be refined. These
functions are the hand-made claims everything else is proved from.

```rust
#[opaque]
#[refined_by(len: int)]
#[invariant(0 <= len)]
pub struct Stack {
    inner: Vec<i32>,
}

impl Stack {
    #[trusted]
    #[spec(fn() -> Stack[0])]
    pub fn new() -> Stack {
        Stack { inner: Vec::new() }
    }

    #[trusted]
    #[spec(fn(self: &mut Stack[@n], i32) ensures self: Stack[n + 1])]
    pub fn push(&mut self, x: i32) {
        self.inner.push(x);
    }

    #[trusted]
    #[spec(fn(self: &mut Stack[@n]) -> i32 requires n > 0 ensures self: Stack[n - 1])]
    pub fn pop(&mut self) -> i32 {
        self.inner.pop().unwrap()
    }

    #[trusted]
    #[spec(fn(&Stack[@n]) -> usize[n])]
    pub fn len(&self) -> usize {
        self.inner.len()
    }

    #[trusted]
    #[spec(fn(&Stack[@n], i: usize{i < n}) -> &i32)]
    pub fn get(&self, i: usize) -> &i32 {
        &self.inner[i]
    }
}

pub fn stack_client() -> i32 {
    let mut s = Stack::new();
    s.push(7);
    s.pop()
}
```

To let `stack[i]` be written, implement `Index` in terms of `get` and mark the
method `trusted_impl`: the spec is taken as given without being compared to
the trait's.

```rust
impl std::ops::Index<usize> for Stack {
    type Output = i32;

    #[trusted_impl]
    #[spec(fn(&Stack[@n], i: usize{i < n}) -> &i32)]
    fn index(&self, i: usize) -> &i32 {
        self.get(i)
    }
}

#[spec(fn(s: &Stack{n: n > 0}) -> i32)]
pub fn bottom(s: &Stack) -> i32 {
    s[0]
}
```

`Vec` from `flux-alloc` already tracks its length this way. Write a vector of
your own only when you need a claim `Vec`'s specs do not make.

## Enums

`reflect` lets specs name the variants of a field-less enum. For enums that
carry data, `refined_by` gives the index and each `variant` says which index
its constructor produces.

```rust
#[reflect]
#[derive(Clone, Copy)]
pub enum Light {
    Red,
    Green,
}

#[spec(fn(l: Light) -> Light{v: v != l})]
pub fn flip(l: Light) -> Light {
    match l {
        Light::Red => Light::Green,
        Light::Green => Light::Red,
    }
}

#[spec(fn(Light[Light::Green]) -> usize[1])]
pub fn go(_l: Light) -> usize {
    1
}

#[refined_by(n: int)]
#[invariant(n >= 0)]
pub enum List {
    #[variant(List[0])]
    Nil,
    #[variant((i32, Box<List[@n]>) -> List[n + 1])]
    Cons(i32, Box<List>),
}

#[spec(fn(&List[@n]) -> bool[n == 0])]
pub fn is_empty(l: &List) -> bool {
    match l {
        List::Nil => true,
        List::Cons(..) => false,
    }
}

#[spec(fn(List[@a], List[@b]) -> List[a + b])]
pub fn append(l1: List, l2: List) -> List {
    match l1 {
        List::Nil => l2,
        List::Cons(h, t) => List::Cons(h, Box::new(append(*t, l2))),
    }
}
```

A variant can constrain what it holds. In a `match`, Flux knows the index of
the arm it is in, so an impossible arm is closed with `flux_rs::unreachable()`,
which requires `false`: Flux must prove the arm cannot be reached.

```rust
#[refined_by(n: int)]
#[invariant(n >= 0)]
pub enum Count {
    #[variant(({i32[@n] | n > 0}) -> Count[n])]
    Some(i32),
    #[variant(Count[0])]
    None,
}

#[spec(fn(Count{n: n > 0}) -> i32{v: v > 0})]
pub fn value(c: Count) -> i32 {
    match c {
        Count::Some(n) => n,
        Count::None => flux_rs::unreachable(),
    }
}
```

## Typestate

An index that records a state lets each method say which state it needs and
which it leaves. Reflected enums make the states readable.

```rust
#[reflect]
pub enum Mode {
    Idle,
    Running,
}

#[opaque]
#[refined_by(mode: Mode)]
pub struct Timer {
    ticks: u32,
}

impl Timer {
    #[trusted]
    #[spec(fn() -> Timer[Mode::Idle])]
    pub fn new() -> Timer {
        Timer { ticks: 0 }
    }

    #[trusted]
    #[spec(fn(self: &mut Timer[Mode::Idle]) ensures self: Timer[Mode::Running])]
    pub fn start(&mut self) {
        self.ticks = 1;
    }

    #[trusted]
    #[spec(fn(self: &mut Timer[Mode::Running]) ensures self: Timer[Mode::Idle])]
    pub fn stop(&mut self) {
        self.ticks = 0;
    }
}

pub fn run_once() {
    let mut t = Timer::new();
    t.start();
    t.stop();
}
```

## Type aliases

An alias names a refined type. Parameters in `[..]` are its indexes; parameters
in `(..)` are supplied where the alias is used.

```rust
#[alias(type Nat[n: int] = {i32[n] | 0 <= n})]
pub type Nat = i32;

#[alias(type AtLeast(lo: int)[v: int] = {i32[v] | lo <= v})]
pub type AtLeast = i32;

#[spec(fn(x: Nat{x < 100}) -> Nat)]
pub fn next(x: Nat) -> Nat {
    x + 1
}

#[spec(fn(x: AtLeast(10)) -> AtLeast(5))]
pub fn loosen(x: AtLeast) -> AtLeast {
    x
}
```
