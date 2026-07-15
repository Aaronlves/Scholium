# Rust engineering and Swift boundary reference

## Toolchain and project policy

- Prefer stable Rust and declare the edition and minimum supported Rust version in `Cargo.toml`.
- Pin a project toolchain only when reproducible packaging requires it; do not silently change a user's global toolchain.
- Keep build-script outputs in Cargo's `OUT_DIR`, emit narrow `rerun-if-changed` directives, and distinguish host from target variables while cross-compiling.
- Keep shipped application and CLI dependencies represented in `Cargo.lock`.
- Treat format, lints, tests, and release compilation as separate gates. Clippy's correctness lints are not a substitute for tests.

Primary references:

- [The Rust Programming Language](https://doc.rust-lang.org/stable/book/)
- [Cargo Reference](https://doc.rust-lang.org/cargo/reference/)
- [Cargo build scripts](https://doc.rust-lang.org/cargo/reference/build-scripts.html)
- [Rust 2024 Edition Guide](https://doc.rust-lang.org/edition-guide/rust-2024/)
- [Clippy lint documentation](https://rust-lang.github.io/rust-clippy/stable/)
- [rustfmt through Cargo](https://doc.rust-lang.org/cargo/commands/cargo-fmt.html)
- [Rust automated testing](https://doc.rust-lang.org/stable/book/ch11-00-testing.html)
- [Rust Fuzz Book](https://rust-fuzz.github.io/book/)
- [Miri](https://github.com/rust-lang/miri)

## Error, panic, and unsafe policy

- Expected environmental and input failures return typed `Result` values.
- A panic represents an internal invariant violation and must not become the ordinary error channel.
- Catch or prevent panics before a C ABI boundary. Never allow unwinding across a non-unwind ABI.
- Mark 2024-edition extern blocks `unsafe`; treat declarations as proof obligations, not as validated APIs.
- Keep unsafe code locally reviewable. Every block states pointer validity, lifetime, aliasing, initialization, thread, and ownership assumptions that make it sound.
- Fuzz parsers and boundary decoders when they accept arbitrary Markdown, metadata, query syntax, or persisted index bytes.

Primary references:

- [Rust Reference: panic](https://doc.rust-lang.org/stable/reference/panic.html)
- [Rustonomicon: FFI](https://doc.rust-lang.org/nomicon/ffi.html)
- [Rustonomicon: unsafe programming](https://doc.rust-lang.org/stable/nomicon/)
- [Rust 2024 unsafe extern blocks](https://doc.rust-lang.org/edition-guide/rust-2024/unsafe-extern.html)

## Swift integration choices

### Persistent local subprocess

Use first when proving a derived engine. Exchange length-delimited or JSON-lines messages over pipes with:

- a protocol version;
- request ID and cancellation ID;
- bounded message sizes;
- explicit UTF-8 handling;
- typed errors without research text;
- restart and full-rebuild behavior.

Advantages: crash isolation, independent CLI tests, easy shadow execution, and no Swift ABI coupling. Cost: process lifecycle and serialization.

### C ABI

Use for a very small stable surface. Export opaque handles plus create/query/free functions. Define allocation ownership, nullability, lengths, threading, cancellation, and destruction explicitly. Catch panics inside Rust and return error values.

### UniFFI

Use after checking the current generated Swift output under Scholium's exact strict-concurrency settings. UniFFI generates C headers/module maps and high-level Swift bindings, but its current guide describes Swift 6 support as partial, including known async `Sendable` limitations. Do not adopt generated bindings without compiling them in the Xcode-beta toolchain.

Primary references:

- [UniFFI guide](https://mozilla.github.io/uniffi-rs/latest/)
- [UniFFI Swift bindings](https://mozilla.github.io/uniffi-rs/latest/swift/overview.html)
- [UniFFI Swift configuration](https://mozilla.github.io/uniffi-rs/latest/swift/configuration.html)

Do not disable UniFFI's binding/library checksum checks. Keep the initial exported API synchronous because the current Swift guide identifies partial Swift 6 support and async `Sendable` limitations. Call blocking work from a Swift actor or other explicitly off-main execution context.

`swift-bridge` is another pre-1.0 generated-binding option. Evaluate it only with a small spike under the exact Xcode-beta strict-concurrency and universal-architecture build; do not choose it from claimed overhead alone. Primary reference: [swift-bridge documentation](https://docs.rs/crate/swift-bridge/latest).

## Performance discipline

- Benchmark a release build on representative fixtures and publish p50, p95, maximum, sample count, index size, and memory peak.
- Keep correctness oracles beside performance data. Faster wrong ranking, stale generations, or lost Unicode is failure.
- Consider PGO only after algorithm, I/O, allocation, and concurrency issues are measured and corrected.

Primary reference: [rustc profile-guided optimization](https://doc.rust-lang.org/rustc/profile-guided-optimization.html).
