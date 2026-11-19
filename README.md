# Monopoly Perú F3182 — Banca digital multijugador

PWA mobile-first para usar junto al tablero físico Monopoly Perú F3182. Incluye salas privadas sin registro, banca, turnos, propiedades, hipotecas, intercambios, subastas, dados físicos o virtuales y cartas El Chamán / La Tómbola.

## Arquitectura

- Astro 7, TypeScript, React Islands y Tailwind CSS 4.
- Supabase PostgreSQL: operaciones transaccionales y sesiones privadas por jugador. Realtime WebSocket sin sondeo periódico.
- Hosting Vercel: Preview de la rama dev/monopoly-app, sin despliegues automáticos a producción.

## Desarrollo local

Node.js 24 y pnpm 10. Ejecutar en la raíz:

    pnpm install --frozen-lockfile
    pnpm dev
    pnpm build

Variables necesarias en .env.local (no versionar):

    PUBLIC_SUPABASE_URL=https://TU_PROYECTO.supabase.co
    PUBLIC_SUPABASE_PUBLISHABLE_KEY=TU_CLAVE_PUBLICA

El frontend estático solo utiliza variables públicas. No incluir claves secretas, tokens de jugador ni credenciales de recuperación en Git.

## Edición F3182

El catálogo de la edición está en database/013_f3182_verified_catalog.sql: 40 casillas y dos barajas de 16 cartas. Las posiciones exactas y los precios de propiedades todavía no se han verificado con las tarjetas de F3182. El anfitrión puede editar casillas sin dueño. No inventar valores ni mezclar la edición de 2010.

## Retos: El Chamán y La Tómbola

Base de datos: database/014_card_challenge_accounting.sql.

1. Una tirada que termina en una de estas casillas crea una carta pendiente para el jugador.
2. No se permite cerrar el turno hasta que se resuelva la carta.
3. El anfitrión transcribe o resume la carta física, registra si el reto se cumplió y el efecto correspondiente.
4. Los efectos disponibles incluyen premio/multa del banco, pago entre jugadores, movimiento, cárcel, liberación o solo anotación.
5. Cada liquidación es atómica y no puede repetirse. Los movimientos monetarios quedan vinculados a la carta mediante room_ledger.card_challenge_id.
6. La interfaz tiene una pestaña Cartas con contadores por baraja, retos cumplidos/incumplidos, pendientes e historial.

Los textos e importes de las 32 cartas físicas todavía no están precargados. Se requieren fotografías legibles para automatizar exactamente sus instrucciones. Movimientos especiales pueden necesitar ajustes complementarios manuales.

## Gestión SQL

Todos los scripts se conservan en el directorio database/ y se ejecutan de manera controlada y numerada, sin migraciones automáticas. No modificar ni repetir scripts previamente aplicados. Versiones 001 a 014 incluyen salas, credenciales, juego, banca, propiedades, subastas, catálogo y cartas.

## Validación del módulo Cartas — noviembre de 2026

- SQL y banca: probados con anfitrión e invitado, incluyendo ambas barajas, bloqueo de turno, abono, cargo, contadores, autorización del anfitrión, rechazo de un segundo cobro y borrado de salas QA.
- Chromium + Playwright: dos navegadores separados en viewport móvil 390 px. Creación de sala, unión, inicio, tiradas, cartas automáticas, resolución, saldos en tiempo real e historial, sin errores JavaScript.
- Compilación Astro + TypeScript: aprobada.
- Pendiente: cotejar las 32 tarjetas físicas originales y sus acciones especiales.

## Despliegue Preview

La rama dev/monopoly-app está preparada para pruebas. El Ignored Build Step de Vercel debe seguir bloqueando los builds automáticos. Para publicar una Preview concreta, exceptuar temporalmente el SHA exacto, desplegar y restaurar el bloqueo. No cambiar main ni producción sin autorización.
