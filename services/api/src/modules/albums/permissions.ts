export type AlbumRole = 'owner' | 'editor' | 'contributor' | 'viewer';

export type AlbumAction =
  | 'view'
  | 'add_own_memories'
  | 'remove_own_memories'
  | 'remove_others_memories'
  | 'edit_album'
  | 'manage_members'
  | 'delete_album';

/** The album role matrix from docs/architecture/security.md. The server enforces it; clients only hide actions. */
const MATRIX: Record<AlbumAction, readonly AlbumRole[]> = {
  view: ['owner', 'editor', 'contributor', 'viewer'],
  add_own_memories: ['owner', 'editor', 'contributor'],
  remove_own_memories: ['owner', 'editor', 'contributor'],
  remove_others_memories: ['owner', 'editor'],
  edit_album: ['owner', 'editor'],
  manage_members: ['owner'],
  delete_album: ['owner'],
};

export function can(role: AlbumRole, action: AlbumAction): boolean {
  return MATRIX[action].includes(role);
}

export const ALL_ACTIONS = Object.keys(MATRIX) as AlbumAction[];
export const ALL_ROLES: readonly AlbumRole[] = ['owner', 'editor', 'contributor', 'viewer'];
