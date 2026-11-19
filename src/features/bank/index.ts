/** Financial operations will be validated server-side in this module. */
export interface BankTransaction {
	id: string;
	amount: number;
	currency: 'PEN';
}
