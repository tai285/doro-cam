# Spec: Albums and Sharing

Status: Draft (Post-MVP, P9) · Last updated: 2026-09-30 · Related: SHR-001–SHR-008, PRIV-002, WEB-007, [security.md](../architecture/security.md)

## Purpose

Let groups (e.g. "Japan Trip 2027" with members A–D) collect original-quality Memories in one place with clear permissions.

## Entities

| Entity | Fields |
|---|---|
| `Album` | `id, ownerId, kind (album \| trip), title, description, startsOn?, endsOn?, coverMemoryId?, allowOriginalDownload (default true), shareLocation (default false), autoAddDuringTrip (default false), createdAt, updatedAt, deletedAt` |
| `AlbumMember` | `albumId, userId, role (owner \| editor \| contributor \| viewer), invitedBy, joinedAt` |
| `AlbumInvite` | `id, albumId, role, tokenHash, createdBy, expiresAt, maxUses, uses, revokedAt` |
| `AlbumItem` | `albumId, memoryId, addedBy, addedAt` |

## Rules

1. Every album has exactly one `owner` member, and it is the `Album.ownerId`. Ownership transfer is an explicit operation (Post).
2. The permission matrix is defined in [security.md](../architecture/security.md#authorization). The server enforces it; the web and mobile clients only hide actions.
3. Adding a Memory to an album does not copy media. Members get access through the `AlbumItem` relation.
4. A Contributor may add only Memories they own.
5. Location is visible to a non-owner only if `album.shareLocation` and the Memory's own location sharing allow it (SHR-006, PRIV-002). Otherwise location fields are omitted and sanitized files are served.
6. Original downloads for non-owners require `allowOriginalDownload`. Otherwise only the rendered and display assets are available.
7. **Trip auto-add** (`autoAddDuringTrip`): Memories a member captures between `startsOn` and `endsOn` (in the capture time zone) are proposed for addition. The member confirms per batch; nothing is added silently.
8. Invites: a random 32-byte token, of which only the hash is stored. Invites expire (default 14 days) and can be revoked. Accepting requires an account.
9. When a member leaves or is removed, their `AlbumItem`s stay unless they remove them. The owner decides; the default is to keep them, and the UI confirms.
10. A Memory deleted by its owner disappears from all albums.

## Error cases

`album.not_found` (404, also used when not a member), `album.forbidden` (403, member lacking the role), `invite.expired`, `invite.revoked`, `invite.exhausted` (410), `album.owner_cannot_leave` (409).

## Acceptance criteria

- API integration tests cover every cell of the permission matrix, both allowed and denied.
- A location-leak test: a Viewer requesting any asset of a Memory with location hidden receives a file whose metadata has no GPS tags, verified by parsing EXIF/MP4 atoms in the test.
