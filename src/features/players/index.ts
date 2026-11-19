/** Player identity within a room; authentication is intentionally out of scope. */
export interface Player {
	id: string;
	name: string;
	roomCode: string;
}
