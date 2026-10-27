def save_request(store, note_id, expected_revision, body):
    store.commit(note_id, expected_revision, body)
    return {"saved": True}
