# Discuss completion routing

Discuss has no generic `agent submit-result` body. Apply the required
`scholium-discussion-protocol`, including its protected response and Record
references, to the one attributed Agent response. Submit that response with
`agent discuss-reply`; the successful operation atomically forms the Research
Record and completes the Discussion.

The Discuss Method governs the philosophical exchange; it does not define the
response modules, field composition, or persistence shape.
