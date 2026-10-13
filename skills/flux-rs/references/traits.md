# Traits and generic refinements

Specs on trait methods, associated refinements, refined associated types,
`impl Trait`, `dyn Trait`, and refinements that are themselves parameters.

```rust
use flux_rs::{assert, attrs::*};
```

## Specs on trait methods

A spec on a trait method is what every caller of the trait may rely on. Each
implementation is checked to be at least as good: it may require less and
promise more. A call through a known type uses that type's own spec.

```rust
pub trait Source {
    #[spec(fn(&Self) -> i32{v: 100 < v})]
    fn level(&self) -> i32;
}

pub struct Full;

impl Source for Full {
    #[spec(fn(&Self) -> i32[2000])]
    fn level(&self) -> i32 {
        2000
    }
}

#[spec(fn(_) -> i32{v: 100 < v})]
pub fn any_level<S: Source>(s: S) -> i32 {
    s.level()
}

#[spec(fn(Full) -> i32[2000])]
pub fn full_level(s: Full) -> i32 {
    s.level()
}

pub trait Step {
    #[spec(fn(x: &mut i32[@n]) requires 100 < n && n < 1000 ensures x: i32{v: n < v})]
    fn step(x: &mut i32);
}

pub struct ByOne;

impl Step for ByOne {
    // Requires less (`0 < n`) and promises more (exactly `n + 1`).
    #[spec(fn(x: &mut i32[@n]) requires 0 < n && n < 1000 ensures x: i32[n + 1])]
    fn step(x: &mut i32) {
        *x += 1;
    }
}
```

## Associated refinements

A trait can declare a spec function that each implementation defines, so one
generic spec means something different per type. Declare it with `reft` on the
trait, define it with `reft` on the impl, and refer to it as
`<T as Trait>::name(..)`. A body on the trait's declaration is the default.

```rust
#[reft(fn in_range(x: int) -> bool)]
pub trait Bounded {
    #[spec(fn() -> i32{v: <Self as Bounded>::in_range(v)})]
    fn sample() -> i32;
}

pub struct Small;

#[reft(fn in_range(x: int) -> bool { 0 <= x && x < 10 })]
impl Bounded for Small {
    #[spec(fn() -> i32[3])]
    fn sample() -> i32 {
        3
    }
}

#[spec(fn() -> i32{v: v < 10})]
pub fn small_sample() -> i32 {
    Small::sample()
}

#[reft(fn bump(x: int) -> int { x + 1 })]
pub trait Bump {}

pub struct Default1;
impl Bump for Default1 {}

pub struct By2;
#[reft(fn bump(x: int) -> int { x + 2 })]
impl Bump for By2 {}

#[spec(fn() -> i32{v: v == <Default1 as Bump>::bump(0)})]
pub fn one() -> i32 {
    1
}

#[spec(fn() -> i32{v: v == <By2 as Bump>::bump(0)})]
pub fn two() -> i32 {
    2
}
```

`assoc` is another spelling of `reft`. The indexing specs in `flux-core` work
this way: `SliceIndex` declares `in_bounds(idx, len)`, each index type defines
it, and `v[i]` requires `<I as SliceIndex<[T]>>::in_bounds(i, len)`.

## Refined associated types

An associated refinement may take the trait's associated types as arguments,
and a method spec may index an associated type directly.

```rust
#[reft(fn can_fit(self: Self, animal: Self::Animal) -> bool)]
pub trait Barn {
    type Animal;

    #[spec(fn(self: &mut Self[@barn], animal: Self::Animal{<Self as Barn>::can_fit(barn, animal)}))]
    fn put(&mut self, animal: Self::Animal);
}

#[refined_by(size: int)]
pub struct Horse {
    #[field(i32[size])]
    pub size: i32,
}

#[refined_by(max_size: int)]
pub struct HorseBarn {
    #[field(i32[max_size])]
    pub max_size: i32,
}

#[reft(fn can_fit(self: HorseBarn, horse: Horse) -> bool { horse.size <= self.max_size })]
impl Barn for HorseBarn {
    type Animal = Horse;

    #[spec(fn(self: &mut Self[@barn], horse: Horse{horse.size <= barn.max_size}))]
    fn put(&mut self, _horse: Horse) {}
}

pub fn stable_a_horse() {
    let mut barn = HorseBarn { max_size: 20 };
    barn.put(Horse { size: 10 });
}

pub trait Echo {
    type Item;

    #[spec(fn(Self::Item[@x]) -> Self::Item[x])]
    fn echo(x: Self::Item) -> Self::Item;
}

impl Echo for () {
    type Item = i32;

    #[spec(fn(x: i32) -> i32[x])]
    fn echo(x: i32) -> i32 {
        x
    }
}

pub fn echo_zero() {
    let x = <() as Echo>::echo(0);
    assert(x == 0);
}
```

## `impl Trait`

The associated types of a returned `impl Trait` can be refined, and callers see
the refinement on what it yields.

```rust
#[spec(fn(x: i32) -> impl Iterator<Item = i32{v: x <= v}>)]
pub fn from(x: i32) -> impl Iterator<Item = i32> {
    Some(x).into_iter()
}

#[spec(fn(k: i32) -> Option<i32{v: k <= v}>)]
pub fn first_from(k: i32) -> Option<i32> {
    let mut it = from(k);
    it.next()
}
```

## `dyn Trait`

A call through a trait object uses the trait's spec, since the implementation
is not known.

```rust
pub trait Shape {
    #[spec(fn(self: _) -> i32{v: 0 <= v})]
    fn vertices(&self) -> i32;
}

pub struct Circle;

impl Shape for Circle {
    #[spec(fn(self: _) -> i32[0])]
    fn vertices(&self) -> i32 {
        0
    }
}

#[spec(fn(shape: _) -> i32{v: 0 <= v})]
pub fn count(shape: &dyn Shape) -> i32 {
    shape.vertices()
}
```

## Generic refinements

A signature can take a refinement as a parameter, written `hrn p: sort -> bool`
in brackets after `fn`. Flux picks the predicate at each call: the strongest
one the arguments satisfy. This is how one spec for `max` serves "is even",
"is one of 4 and 10" and every other property.

```rust
#[spec(fn[hrn p: int -> bool](x: i32, y: i32) -> i32{v: p(v) && v >= x && v >= y}
       requires p(x) && p(y))]
pub fn max(x: i32, y: i32) -> i32 {
    if x > y { x } else { y }
}

#[spec(fn() -> i32{v: v % 2 == 0})]
pub fn even_max() -> i32 {
    max(4, 10)
}

#[spec(fn() -> i32[10])]
pub fn ten() -> i32 {
    max(4, 10)
}
```

A struct can be indexed by a predicate too. It is written at a use site as a
closure, and bound with `@` like any index.

```rust
#[refined_by(a: int, b: int, hrn p: (int, int) -> bool)]
pub struct Pair {
    #[field(i32[a])]
    fst: i32,
    #[field({i32[b] | p(a, b)})]
    snd: i32,
}

#[spec(fn(Pair[@a, @b, |a, b| a < b && b - a < 100]) -> i32{v: v > 0})]
pub fn gap(pair: Pair) -> i32 {
    pair.snd - pair.fst
}

pub fn gap_of_one() -> i32 {
    gap(Pair { fst: 0, snd: 1 })
}

#[derive(Clone, Copy)]
#[refined_by(hrn p: int -> bool)]
pub struct Check;

#[spec(fn(x: i32) -> Check[|y| y > x])]
pub fn above(_x: i32) -> Check {
    Check
}

#[spec(fn(x: i32) -> Check[|y| y < x])]
pub fn below(_x: i32) -> Check {
    Check
}

#[spec(fn(Check[@p1], Check[@p2]) -> Check[|x| p1(x) || p2(x)])]
pub fn either(_: Check, _: Check) -> Check {
    Check
}

#[spec(fn(Check[@p], x: i32{p(x)}))]
pub fn passes(_: Check, _x: i32) {}

pub fn outside_zero_to_ten() {
    let c = either(above(10), below(0));
    passes(c, 11);
    passes(c, -1);
}
```

A trait method with a generic refinement needs the same parameter on every
implementation's spec.
