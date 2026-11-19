## Project: Monopoly Perú

Hybrid multiplayer Monopoly banking application.

### Tech Stack
- Astro 7 + TypeScript strict
- React Islands for interactive components
- Tailwind CSS 4
- pnpm as package manager
- Supabase PostgreSQL
- Supabase Realtime using WebSockets
- Vercel deployment

### Architecture
- Mobile-first PWA.
- Prefer Astro components for static UI.
- Use React only for interactive components.
- Organize code by functional modules.
- Keep business logic separate from UI.
- Follow Modern Web Guidance when available.

### Game Rules
- No user registration or login.
- Players join private rooms using invite codes.
- Maximum players defined by the Monopoly edition.
- Rooms close automatically when games start.
- Support physical and virtual dice.
- Physical dice results are entered manually.
- Virtual dice results are generated server-side.
- The physical board remains the primary game.
- Virtual banking manages financial transactions.
- Synchronize game events through WebSockets.
- No periodic polling.

### Development Rules
- Use pnpm exclusively.
- Follow TypeScript strict typing.
- Avoid unnecessary dependencies.
- Never expose Supabase service credentials.
- Validate financial operations server-side.
- Implement one feature at a time.
- Do not modify unrelated modules.
- Run checks after changes.
- Explain significant technical decisions.