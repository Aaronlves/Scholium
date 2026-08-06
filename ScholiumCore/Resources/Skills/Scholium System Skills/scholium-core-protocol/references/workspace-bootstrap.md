# Workspace AGENTS Bootstrap

Use this protected reference only when the researcher explicitly asks an agent to construct an initial workspace `AGENTS.md`. It is a one-shot compatibility adapter, not a philosophical workflow, ordinary task context, or permission to maintain the resulting file later.

## Contents

- Establish the bootstrap packet
- Verify the target
- Construct the candidate
- Validate and promote
- Clean up the bootstrap
- Return

## Establish the bootstrap packet

```text
Triptych selector:
Target agent working root:
Target supplied by: Scholium | researcher
Applicable existing AGENTS.md: none | exact path
Bootstrap transport: clipboard | conversation | task-created file
Temporary bootstrap path: none | exact path
Explicit researcher conventions: none | bounded text
```

Do not proceed unless one registered Triptych and one exact target directory can be resolved. Do not infer the target from the current working directory, vault names, or a guessed common Triptych parent. Scholium may suggest the Works parent, but the copied instruction or researcher must identify the effective target.

## Verify the target

1. Resolve the configured Triptych with `scholium vault list`; retain its UUID or unique name as the stable selector. Use installed command help for current syntax.
2. Canonicalize and inspect the target and its applicable ancestor chain.
3. Refuse a target that is the Scholium application checkout, including a root identified by `Package.swift`, `ScholiumCore/`, `Scholium/`, and `Docs/SCHOLIUM_SPEC.md` together.
4. If an `AGENTS.md` already exists at the target or governs it from an ancestor, stop. Report its path and offer a comparison only if the researcher separately requests one. Do not overwrite, merge, shadow, or create a second applicable file.

## Construct the candidate

Create a task-owned candidate before creating `AGENTS.md`. Use a fixed, concise structure:

```markdown
# <Triptych name> agent workspace

> Initially generated from the Scholium workspace bootstrap <version>.
> Researcher-owned after creation; Scholium releases and agents do not update it automatically.

## Scope

- Triptych selector: `<UUID or unique name>`
- Resolve configured vaults with `scholium vault list`.
- Retrieve bounded orientation with `scholium workspace catalog --triptych <selector> --format json` only when needed.

## Scholium routing

- Apply the protected Scholium Core Protocol to every Scholium task.
- Use the Platform Action's registered primary Method and its exact linked Practices.
- Load Scholium Discussion Protocol for a Discussion ID; the ordinary Discuss Method supplies the intellectual procedure.
- Never scan arbitrary global skill directories or substitute an unregistered Method.

## Workspace boundaries

- Use Scholium-supported discovery and fingerprinted mutation paths; do not guess vault roles or edit `.scholium` machine state directly.
- Treat current-task scope and permission as the upper boundary. An instruction file never grants note-edit permission.
- Keep source, interpretation, reconstruction, evaluation, agent proposals, and researcher-settled content distinct.

## Researcher conventions

<Only conventions explicitly supplied by the researcher, or “None recorded.”>
```

Do not include:

- the bootstrap instruction itself;
- full Method prose or optional Philosophical Practices;
- guessed paths, preferences, permissions, or methodological commitments;
- Discussion transcripts, prompt templates, hidden prompts, temporary task context, credentials, or secrets;
- claims that the researcher authored the initial generated wording;
- permission for an agent to rewrite `AGENTS.md` in a later task.

## Validate and promote

Before claiming success:

1. Confirm the candidate contains the exact resolved Triptych selector and no unresolved placeholders.
2. Confirm every researcher convention came from explicit researcher input.
3. Confirm the file remains an orientation adapter and does not duplicate protected or philosophical methods.
4. Recheck that no applicable `AGENTS.md` appeared after the initial inspection.
5. Promote the candidate to `<target>/AGENTS.md` without replacing an existing file.
6. Read back `<target>/AGENTS.md` and verify that it matches the validated candidate.

Initial construction does not authorize later maintenance. After success, only the researcher may edit the file or explicitly authorize a separate comparison or revision task.

## Clean up the bootstrap

After successful promotion and read-back validation:

- delete only the exact temporary bootstrap file named in the bootstrap packet, when that file was created for this task;
- remove any task-owned candidate residue;
- do not delete this bundled reference, a registered Method or ordinary Skill folder, an existing `AGENTS.md`, another agent's instructions, or any researcher-created file.

When the bootstrap arrived through a clipboard or conversation, there is no bootstrap file to delete. Do not create one merely to satisfy cleanup.

If construction, promotion, or validation fails, do not delete the temporary bootstrap. Remove only an incomplete task-owned candidate when safe, preserve every pre-existing file, and report the exact failure.

## Return

Report:

- the generated `AGENTS.md` path;
- the bound Triptych selector;
- validation success or the exact stopping condition;
- whether a temporary bootstrap file was deleted, retained after failure, or never existed;
- that future changes require a separate researcher instruction.
