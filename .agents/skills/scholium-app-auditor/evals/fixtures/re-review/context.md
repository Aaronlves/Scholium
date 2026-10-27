# Synthetic save-response review

This standalone Python fixture represents a storage owner and a request adapter.
It is not Scholium application code or a historical incident. `store.py` and
`before.py` form the reviewed v2 baseline; the supplied candidate replaces only
the adapter. There are no other callers or background tasks in this fixture.

The requested v3 change adds the committed revision to a successful save reply.
The contract is:

- The request's expected revision identifies the version the researcher edited.
- A revision mismatch raises `Conflict`, preserves the current note, and reaches
  the requester as a conflict. A save reply describes a successful commit.
- A successful commit preserves the supplied bytes, including whitespace;
  an empty document is valid. It increments and returns the committed revision.
- No further researcher instruction or replacement expected revision arrives
  while this request is running.
- `note_count` should count all stored notes, but it is outside this save change.

Earlier review dispositions:

| ID | Earlier observation | Disposition at v2 |
|---|---|---|
| R1 | v1 `Store.commit` ignored the expected revision. | Fixed in v2 by checking it before writing. Verify rather than assuming the repair remains effective. |
| R2 | The adapter should strip whitespace and reject an empty document. | Dismissed: the exact-byte and empty-document contracts explicitly permit these inputs. |
| R3 | `note_count` reports one fewer note. | Confirmed pre-existing issue, unchanged in v2; deferred outside the save patch. |
