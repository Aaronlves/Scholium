def save_request(store, note_id, expected_revision, body):
    revision = store.commit(note_id, expected_revision, body)
    return {"saved": True, "revision": revision}
