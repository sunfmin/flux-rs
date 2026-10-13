# Sets, maps and bitvectors

Indexes that are not numbers: which elements a collection holds, what a key
maps to, and the bits of a machine word.

```rust
use flux_rs::{assert, attrs::*, bitvec::BV32, defs};
```

## Sets

`Set<T>` is a sort with the built-in functions `set_empty(0)`,
`set_singleton(x)`, `set_union(a, b)`, `set_intersection(a, b)`,
`set_difference(a, b)`, `set_is_in(x, s)` and `set_subset(a, b)`. Index an
opaque wrapper by the set of its members and state each operation's effect.

```rust
use std::{collections::HashSet, hash::Hash};

defs! {
    fn set_add<T>(x: T, s: Set<T>) -> Set<T> { set_union(set_singleton(x), s) }
    fn set_del<T>(x: T, s: Set<T>) -> Set<T> { set_difference(s, set_singleton(x)) }
}

#[opaque]
#[refined_by(elems: Set<T>)]
pub struct RSet<T> {
    inner: HashSet<T>,
}

impl<T: Eq + Hash> RSet<T> {
    #[trusted]
    #[spec(fn() -> RSet<T>[set_empty(0)])]
    pub fn new() -> RSet<T> {
        RSet { inner: HashSet::new() }
    }

    #[trusted]
    #[spec(fn(self: &mut RSet<T>[@s], elem: T) ensures self: RSet<T>[set_add(elem, s)])]
    pub fn insert(&mut self, elem: T) {
        self.inner.insert(elem);
    }

    #[trusted]
    #[spec(fn(&RSet<T>[@s], &T[@elem]) -> bool[set_is_in(elem, s)])]
    pub fn contains(&self, elem: &T) -> bool {
        self.inner.contains(elem)
    }
}

pub fn members() {
    let mut s = RSet::new();
    s.insert(1);
    s.insert(2);
    assert(s.contains(&1));
    assert(!s.contains(&3));
}

// A permission check: the caller must hold the permission it uses.
#[spec(fn(held: &RSet<i32>[@ps], needed: i32{set_is_in(needed, ps)}))]
pub fn act(_held: &RSet<i32>, _needed: i32) {}

pub fn act_with_permission() {
    let mut held = RSet::new();
    held.insert(7);
    act(&held, 7);
}
```

## Maps

`Map<K, V>` has `map_select(m, k)` for the value at a key and
`map_store(m, k, v)` for the map with one key changed, and `map_default(v)`
for the map holding `v` at every key.

```rust
use std::collections::HashMap;

#[opaque]
#[refined_by(vals: Map<K, V>)]
pub struct RMap<K, V> {
    inner: HashMap<K, V>,
}

impl<K: Eq + Hash, V> RMap<K, V> {
    #[trusted]
    #[spec(fn(self: &mut RMap<K, V>[@m], k: K, v: V) ensures self: RMap<K, V>[map_store(m, k, v)])]
    pub fn set(&mut self, k: K, v: V) {
        self.inner.insert(k, v);
    }

    #[trusted]
    #[spec(fn(&RMap<K, V>[@m], &K[@k]) -> Option<&V[map_select(m, k)]>)]
    pub fn get(&self, k: &K) -> Option<&V> {
        self.inner.get(k)
    }
}

pub fn read_back(m: &mut RMap<i32, i32>) {
    m.set(1, 10);
    if let Some(v) = m.get(&1) {
        assert(*v == 10);
    }
}
```

## Bitvectors

`flux_rs::bitvec::BV32` (and `BV8`) is a word whose index has sort
`bitvec<32>`, so `&`, `|`, `^`, `<<`, `>>` and the arithmetic operators are
reasoned about bit for bit. Integer literals in a bitvector position are read
as bitvectors; `bv_int_to_bv32(n)` converts explicitly.

```rust
#[spec(fn(x: BV32) -> BV32[x + 1])]
pub fn next(x: BV32) -> BV32 {
    x + BV32::new(1)
}

#[spec(fn() -> BV32[bv_int_to_bv32(0x5)])]
pub fn five() -> BV32 {
    BV32::new(0x5)
}

#[spec(fn(x: BV32{x == 10}) -> BV32[2])]
pub fn low_bits(x: BV32) -> BV32 {
    x & BV32::new(3)
}

#[spec(fn(x: BV32, y: BV32) -> bool[x + y > 5])]
pub fn sum_above_five(x: BV32, y: BV32) -> bool {
    x + y > BV32::new(5)
}
```

Spec functions and theorems over bitvectors read like the bit tricks they
state:

```rust
defs! {
    fn is_pow2(x: bitvec<32>) -> bool { (x > 0) && ((x & x - 1) == 0) }
}

#[spec(fn(x: BV32) requires is_pow2(x) && 8 <= x ensures x % 8 == 0)]
pub fn pow2_from_eight_is_octet(_x: BV32) {}
```

Each operator also has a named form, needed where signedness matters:
`bv_add bv_sub bv_mul bv_neg`, `bv_udiv bv_urem bv_sdiv bv_srem`,
`bv_and bv_or bv_xor bv_not`, `bv_shl bv_lshr bv_ashr`, and the comparisons
`bv_ule bv_ult bv_uge bv_ugt` (unsigned) and `bv_sle bv_slt bv_sge bv_sgt`
(signed).

### Constants

Flux cannot read the value out of a constant of a bitvector type. The
`constant` attribute gives it one, which specs then use by name.

```rust
#[constant(bv_int_to_bv32(0x4567))]
pub const START: BV32 = BV32::new(0x4567);

defs! {
    fn is_start(x: bitvec<32>) -> bool { x == START }
}

#[spec(fn() -> BV32{v: is_start(v)})]
pub fn start() -> BV32 {
    BV32::new(0x4567)
}
```

### Widths and integers

`bv_int_to_bvN` and `bv_bvN_to_int`, for N of 8, 32, 64 and 128, move between
a number and a word; `bv_zero_extend_32_to_64` and `bv_sign_extend_32_to_64`
widen. A wrapper of
your own takes the same shape as `BV32`: opaque, indexed by a `bitvec<N>`,
with trusted operations.

```rust
#[opaque]
#[refined_by(v: bitvec<32>)]
pub struct Register {
    inner: u32,
}

impl Register {
    #[trusted]
    #[spec(fn(u32[@n]) -> Register[bv_int_to_bv32(n)])]
    pub fn new(v: u32) -> Register {
        Register { inner: v }
    }

    #[trusted]
    #[spec(fn(&Register[@n]) -> u64[bv_bv64_to_int(bv_zero_extend_32_to_64(n))])]
    pub fn zero_extend(&self) -> u64 {
        self.inner as u64
    }
}

pub fn widened() {
    let r = Register::new(u32::MAX);
    assert(r.zero_extend() == u32::MAX as u64);
}
```
