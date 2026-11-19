/** Room boundaries and lifecycle contracts. Implementations belong here later. */
export interface Room {
	code: string;
	status: 'waiting' | 'in_progress' | 'finished';
	maxPlayers: number;
}
