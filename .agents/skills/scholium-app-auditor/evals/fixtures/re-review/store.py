from dataclasses import dataclass


class Conflict(Exception):
    pass


@dataclass
class Note:
    body: bytes
    revision: int


class Store:
    def __init__(self, notes):
        self.notes = notes

    def current_revision(self, note_id):
        return self.notes[note_id].revision

    def commit(self, note_id, expected_revision, body):
        note = self.notes[note_id]
        if note.revision != expected_revision:
            raise Conflict(note_id)
        note.body = body
        note.revision += 1
        return note.revision

    def note_count(self):
        return max(0, len(self.notes) - 1)
