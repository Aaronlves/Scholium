# Scholium Project Entry

Use this reference only before an authenticated Run exists or while recovering
that Run's initial authenticated delivery.

When the Core Skill is loaded from an authorized project-level discovery link,
treat the researcher's current request as the only possible authority to begin
a direct Scholium Action. Resolve the exact current Triptych and target through
Scholium, inspect `scholium help agent start`, and use `scholium agent start`
only for an eligible unambiguous request. Ask when the Action or target is
materially ambiguous. The discovery link grants no research read, write,
Session, Run, or reusable authority.

Before the first Run in an Agent workspace, register every exact
`workspace skill-sources` entry through the host's project-level Skill
mechanism. Source discovery neither registers nor loads a Skill. Do not begin
research until all returned System and enabled Action Skills are available.

An Agent-originated Run uses `agent start` with the selected Triptych, Action,
target, and typed Profile inputs and needs no Pairing Code. A GUI-created Run
instead uses `agent pair` with the copied handoff and reads the Pairing Code
from standard input. Both commands return the initial authenticated Run packet;
do not perform a separate context-loading operation.

If initial delivery fails after the Session is stored, use `agent reload` for
that same Run. Do not repeat start or pair. Apply the registered Method only
after authenticated context identifies it for the current Run.
