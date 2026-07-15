---
name: rust-language
description: Design, implement, review, debug, or test safe Rust libraries, command-line tools, and Swift-facing native components in the Scholium workspace. Use for Cargo workspaces and manifests, ownership and borrowing, traits and generics, error design, concurrency, performance-sensitive code, unsafe code, C ABI or UniFFI boundaries, Rust packaging, clippy/rustfmt, and deciding whether a component belongs in Rust. Do not use for Swift-only application work or to justify a Rust rewrite without a measured requirement.
---

# Rust Language

Use Rust for a bounded capability with a written success condition. Preserve Scholium's Swift-owned vault trust boundary.

## Establish the environment

1. Locate the Scholium repository root from `AGENTS.md` and `Package.swift`; do not infer it from this skill's installed path.
2. Read `AGENTS.md`, `README.md`, the directly affected Swift protocol, and any existing `Cargo.toml` or `rust-toolchain.toml`.
3. Run `rustc --version`, `cargo --version`, `rustup show active-toolchain`, `cargo clippy --version`, and `cargo fmt --version` before relying on a toolchain.
4. If Rust is absent, report that fact. Do not install rustup, a compiler, targets, or crates globally unless the user authorizes installation.
5. Record the edition, `rust-version`/MSRV, targets, crate types, and release profile before changing build configuration.

Read [references/rust-engineering-and-ffi.md](references/rust-engineering-and-ffi.md) for current Cargo, safety, dependency, and Swift-boundary guidance.

## Decide whether Rust belongs

Require at least one concrete reason:

- a measured CPU, memory, or latency bottleneck;
- a portable core or CLI required on non-Apple platforms;
- an audited Rust library provides a difficult capability more safely;
- process isolation materially reduces the impact of parsing untrusted data.

Keep work in Swift when it primarily concerns SwiftUI/AppKit, security-scoped bookmarks, file coordination, proposal approval, snapshots, or authoritative vault writes. Prefer a small Rust experiment over a rewrite.

## Design the crate boundary first

- Pass immutable values with explicit ownership. Avoid exposing Rust references, pointers, collection internals, or lifetimes to Swift.
- Use versioned request/response records and stable error codes. Keep research content out of logs and panic messages.
- Return `Result` for expected failure. Do not use `unwrap`, `expect`, indexing that may panic, or process exit in library and FFI paths.
- Keep `unsafe` absent by default. When unavoidable, isolate it in a small module, document every safety invariant, and wrap it with a safe API and adversarial tests.
- Use `#![forbid(unsafe_code)]` in pure domain crates when possible; keep any unavoidable bridge `unsafe` in a thin adapter crate.
- Never allow a panic or foreign exception to cross an FFI boundary.
- Prefer a persistent subprocess with a versioned local protocol for the first experiment because it is independently testable and crash-isolated. Consider UniFFI/static linking only after the protocol stabilizes; verify its current Swift 6 limitations first.
- Keep authoritative paths, revision checks, snapshots, validation, approval, and writes in Swift. A Rust component may return derived results or proposals, never apply them.

## Implement idiomatically

- Model valid states with enums and newtypes rather than strings and booleans.
- Borrow inputs when ownership is unnecessary; return owned boundary values.
- Prefer iterators and exhaustive `match` over manual indexing and partial branching.
- Keep public APIs small and document errors, panics, safety, and complexity when relevant.
- Use structured cancellation and bounded concurrency. Do not hold blocking locks across long computation, callbacks, or async suspension.
- Pin intentional dependencies in `Cargo.lock` for shipped binaries. Audit feature flags, licenses, maintenance, native build requirements, and transitive size before adding a crate.
- Do not optimize from intuition. Establish release-build evidence, then narrow allocations, copies, algorithms, or I/O.

## Verify

Run the applicable gates from the crate or workspace root:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo build --workspace --release
cargo doc --workspace --all-features --no-deps
```

Adjust `--all-features` only when features are intentionally incompatible, and explain the tested matrix. Add unit, integration, property, corruption, cancellation, and FFI round-trip tests in proportion to risk. Use fuzzing or Miri for parser and unsafe-sensitive boundaries when justified, clearly labelling any nightly toolchain. Build and test both `aarch64-apple-darwin` and `x86_64-apple-darwin` before packaging a universal application.

For a Swift integration, also run Scholium's Swift tests and package verification. Report the Rust/Swift versions, target triples, commands, measured benefit, unsafe surface, boundary design, and anything not exercised.
