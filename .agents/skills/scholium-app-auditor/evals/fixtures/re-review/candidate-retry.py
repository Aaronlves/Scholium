from store import Conflict


def save_request(store, note_id, expected_revision, body):
    try:
        revision = store.commit(note_id, expected_revision, body)
    except Conflict:
        revision = store.commit(note_id, store.current_revision(note_id), body)
    return {"saved": True, "revision": revision}
