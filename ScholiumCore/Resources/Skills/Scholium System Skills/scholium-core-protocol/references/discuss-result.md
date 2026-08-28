# Discuss completion routing

Discuss has no generic `agent submit-result` body. Apply the required
`scholium-discussion-protocol`, including its protected response and Record
references, for each attributed Agent turn and for Finish. Use
`agent finish-discussion` only after the final durable Agent turn.

The Discuss Method governs the philosophical exchange; it does not define the
response modules, field composition, persistence shape, or Finish payload.
