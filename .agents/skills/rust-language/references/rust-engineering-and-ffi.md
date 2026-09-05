# Rust engineering and Swift boundary

Use this only after the Rust skill's adoption gate identifies a bounded,
measured need. Resolve exact toolchain, edition, platform, dependency, and
binding behavior from the live repository and current primary documentation.

## Rust boundary

- Keep expected input and environmental failure in typed results. Panic is an
  internal invariant failure and must not unwind across a foreign boundary.
- Keep unsafe code local and state the pointer, lifetime, aliasing,
  initialization, ownership, threading, and destruction assumptions that make
  it sound.
- Bound and fuzz parsers or decoders that receive untrusted source, metadata,
  query, or persisted derived data.
- Pin project inputs only where reproducible builds require it; never mutate the
  researcher's global toolchain as an implementation shortcut.

## Swift integration decision

Choose the narrowest mechanism supported by live evidence:

- a supervised local process when crash isolation, shadow comparison, and
  independent recovery matter;
- a small C-compatible interface when a stable synchronous surface and explicit
  memory ownership are sufficient; or
- generated bindings only after generated Swift compiles under the selected
  concurrency, deployment, and packaging environment.

Whichever mechanism is chosen must define versioning, request identity,
cancellation, bounded messages, encoding, typed errors, memory ownership,
threading, teardown, crash behavior, restart, and recovery. Keep research text
out of diagnostics and prevent blocking work from reaching the UI actor.

## Evidence

Verify format, lints, focused tests, boundary tests, release compilation,
supported packaging architectures, notices, failure isolation, and recovery as
separate claims. Measure only after correctness; compare against the live Swift
baseline with the same fixture and oracle.

Primary references: [Rust book](https://doc.rust-lang.org/stable/book/),
[Cargo](https://doc.rust-lang.org/cargo/reference/),
[Rustonomicon FFI](https://doc.rust-lang.org/nomicon/ffi.html), and the current
documentation for any selected binding generator.
