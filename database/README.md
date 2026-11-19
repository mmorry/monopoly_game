# Esquema inicial de base de datos

Estos scripts están preparados para ejecución manual en el **Supabase SQL Editor**. No son migraciones de Supabase CLI y no se deben ejecutar automáticamente desde la aplicación.

## Orden de ejecución

1. Revisa `001_initial_rooms.sql` y ejecútalo una sola vez en el proyecto de Supabase objetivo.
2. Ejecuta `002_verify_initial_rooms.sql` inmediatamente después.
3. Ejecuta `003_create_room.sql` solo después de aprobar la implementación de creación segura.
4. Ejecuta `004_host_security.sql` solo después de revisar sus guardas y consultas de verificación.
5. Registra la fecha, el proyecto y el resultado en la tabla de control de este documento.

No ejecutes el script `001` de nuevo si ya fue aplicado: crea las tablas e índices sin cláusulas idempotentes para revelar errores de entorno o de orden de ejecución.

## Alcance de la versión 001

- `public.rooms` almacena el código de invitación, nombre opcional, límite de jugadores y ciclo de vida `waiting`, `active` o `finished`.
- `public.room_players` almacena alias, ficha (`token`), rol (`host` o `player`) y presencia (`connected`, `disconnected` o `left`). El anfitrión es el único participante con rol `host` por sala.
- Las restricciones verifican formato, longitudes, estados y consistencia de las marcas de tiempo.
- Las claves e índices cubren la relación sala-participantes, alias únicos sin distinción de mayúsculas, fichas no repetidas y el anfitrión único.

## Seguridad inicial

El script que crea las tablas también habilita RLS y revoca todos los permisos de `anon` y `authenticated`. No hay políticas RLS ni permisos de cliente en esta versión; por tanto, ningún navegador puede leer o escribir las tablas directamente.

La creación de salas, la asignación de anfitrión, los cambios de estado y cualquier futuro acceso deben llegar en un script posterior junto con una estrategia de autorización validada del lado servidor. No se deben añadir políticas `USING (true)` ni permisos públicos de escritura.

## Seguridad de credencial del anfitrión

La versión `003` guarda solo el HMAC de la credencial de recuperación y de las sesiones opacas del anfitrión. La versión `004` agrega emisión, vencimiento y revocación de esa credencial. El endpoint futuro debe aceptar una credencial únicamente si su HMAC coincide, no está revocada, no venció y la sala no finalizó; al revocarla debe revocar las sesiones activas dentro de la misma transacción.

`004_host_security.sql` se detiene si encuentra salas existentes. Esta guarda evita aplicar vencimientos por defecto a datos reales; cualquier entorno con salas deberá usar un script de transición revisado de forma independiente.

## Verificaciones esperadas

Al ejecutar `002_verify_initial_rooms.sql`:

- la primera consulta devuelve `rooms` y `room_players` con `row_security_enabled = true`;
- la consulta de restricciones devuelve las restricciones de las dos tablas;
- la consulta de índices muestra las claves e índices definidos en `001`;
- la consulta de privilegios no devuelve filas para `anon` ni `authenticated`.

## Registro de scripts aplicados

| Versión | Archivo | Fecha (America/Lima) | Proyecto de Supabase | Ejecutado por | Resultado |
| --- | --- | --- | --- | --- | --- |
| 001 | `001_initial_rooms.sql` | Pendiente | Pendiente | Pendiente | Pendiente de revisión |
| 002 | `002_verify_initial_rooms.sql` | Pendiente | Pendiente | Pendiente | Pendiente de revisión |
| 003 | `003_create_room.sql` | No registrada | Pendiente | Pendiente | Aplicado; tabla y hash verificados |
| 004 | `004_host_security.sql` | Pendiente | Pendiente | Pendiente | Pendiente de revisión |
