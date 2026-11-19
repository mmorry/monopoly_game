type FormField = HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement;

function linkError(field: FormField, shown: boolean) {
	const errorId = field.dataset.error;
	if (!errorId) return;

	const descriptions = (field.getAttribute('aria-describedby') ?? '')
		.split(/\s+/)
		.filter((id) => id && id !== errorId);

	if (shown) descriptions.push(errorId);

	if (descriptions.length) {
		field.setAttribute('aria-describedby', descriptions.join(' '));
	} else {
		field.removeAttribute('aria-describedby');
	}
}

function syncAria(field: EventTarget | null) {
	if (!(field instanceof HTMLInputElement || field instanceof HTMLSelectElement || field instanceof HTMLTextAreaElement)) return;

	const invalid = field.matches(':user-invalid');
	field.setAttribute('aria-invalid', invalid ? 'true' : 'false');
	linkError(field, invalid);
}

export function initialiseAccessibleFormValidation(form: HTMLFormElement) {
	const fields = form.querySelectorAll<FormField>('input, select, textarea');
	fields.forEach((field) => field.setAttribute('aria-invalid', 'false'));

	form.addEventListener('blur', (event) => syncAria(event.target), true);
	form.addEventListener('input', (event) => syncAria(event.target));
	form.addEventListener('change', (event) => syncAria(event.target));
	form.addEventListener('invalid', (event) => syncAria(event.target), true);

	form.addEventListener('submit', (event) => {
		event.preventDefault();

		const status = form.querySelector<HTMLElement>('[data-form-status]');
		if (status) {
			status.textContent = 'Las salas todavía no están disponibles. No se envió información.';
		}
	});
}
