# Swift API naming

Read the declaration and representative call sites against current project
terminology and the official [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
Judge clarity in complete calls, not isolated names.

- Identify the receiver, argument roles, side effects, return value, and any
  mutating/nonmutating relationship. Make those distinctions grammatical.
- Prefer clarity over brevity; labels should disambiguate semantic roles rather
  than repeat types. Prefer a coherent defaulted API over redundant families.
- Check overload resolution, protocol requirements, coupled serialized names,
  and every repository-owned caller before applying a rename. Preserve behavior;
  remove the superseded name rather than retaining forwarding aliases.
- Document non-obvious purpose, safety, effects, errors, and cost. Do not merely
  restate declarations.

A naming review alone does not authorize an isolation change, lint policy, or
refactor. If those are also requested, load their relevant guidance and evidence.
