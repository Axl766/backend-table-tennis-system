# Auth Standard

The auth surface of this stack: token kinds and minting, where tokens travel,
the three middlewares, the auth endpoints, the rate limiter, and the env seam
additions. Distilled from the reference codebase — the code must read like home.

> Applies to all code this standard touches (SKILL.md §Compliance). Known
> deviations live in the **Debt** section at the bottom — bring touched code into
> conformance; record found-but-unfixed deviations there.

## 1. Stack facts — what minting and hashing look like here

- **JWT HS256 minted with `node:crypto`** (`createHmac`) — no `jsonwebtoken`
  dependency; the token format never reaches controllers (they only see claims).
- **Two token kinds**, each with its own secret and TTL from env:
  access (short) and refresh (long). `verifyToken` returns `null` on anything
  tampered, malformed or expired — callers translate `null` into the uniform
  `401`.
- **Passwords hash with `@node-rs/argon2`** (verify on login, hash on create /
  change); hashing lives in the auth module and never leaks elsewhere.
- **`isActive` re-check on every request** (the middleware re-reads the account
  through the model): deactivating a user kills their live session on the
  following request, and a deleted account stops answering entirely — no
  token-revocation list needed.

## 2. Token placement — the standard clients must meet

| Token | Where it travels | Why |
|---|---|---|
| **access** | The **login/refresh response body → client memory only** (a JS variable in a browser client). **Never persisted** — no localStorage, no cookies for it. TTL short (`JWT_ACCESS_TTL`) | A stolen access token dies in minutes; the XSS payoff shrinks to nothing worth having |
| **refresh** | **An `httpOnly` cookie only**: `httpOnly: true`, `secure: env.NODE_ENV === "production"`, `sameSite: "strict"`, `path: "/api/v1/auth"` (subtree-scoped so logout can clear it), `maxAge: JWT_REFRESH_TTL * 1000` | `httpOnly` keeps it invisible to JS (the XSS move dies); `SameSite=strict` takes CSRF off the table; the path keeps it from riding every request |

Rules that follow:

- **Rotation**: every successful `POST /auth/refresh` mints a **new refresh
  cookie** (and a new access token) — the delivered one is replaced, never
  reused as-is.
- **Stateless honesty**: rotation narrows the replay window but a leaked
  pre-rotation refresh stays valid until expiry — single-use refresh with
  server-side reuse-detection is stateful and is a **separate design**
  (deferred, like the revocation list).
- **Logout** clears the refresh cookie (`res.clearCookie` with the same
  `path`) — the cookie can then no longer mint sessions.
- **No response body ever carries the refresh token** from now on.
- The refresh endpoint reads the cookie (`req.cookies.refreshToken` via
  `cookieParser`, conventions.md §9); a missing/expired one → the uniform
  `401`.

## 3. The three middlewares — `modules/auth/auth.middleware.ts`

They attach `req.user` (typed in `shared/types/express.d.ts` — the single
`declare global`, conventions.md §6):

```ts
export const authenticate = async (req, res, next) => {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) throw ApiError.unauthorized("Missing bearer token");
  const payload = verifyToken(header.slice(7), "access");
  if (!payload) throw ApiError.unauthorized("Invalid or expired token");
  const user = await AuthModel.getActiveById(payload.sub);
  if (!user) throw ApiError.unauthorized("Account is inactive");
  req.user = user;
  return next();
};
```

- `authenticate` — hard gate; every router leaves it first when the whole
  resource is protected.
- `optionalAuthenticate` — absent token continues anonymous (no `req.user`),
  but a **present** token must be valid and live: a forged or stale token never
  sneaks through a public endpoint.
- `authorize(...roles)` — per-resource role guard: the router **declares who
  may call each endpoint**; missing `req.user` → `401`, wrong role → `403`.

## 4. Endpoints — `POST /api/v1/auth/*` only

| Endpoint | Behavior |
|---|---|
| `POST /auth/login` | Verify `isActive` + argon2 verify; mint access (body) + refresh (set cookie) |
| `POST /auth/refresh` | Verify the **cookie's** refresh token; rotate — new refresh cookie + new access in body |
| `POST /auth/logout` | Clear the refresh cookie; empty success envelope, `data: null` |

- Account creation is a **domain policy**, not an auth endpoint: no public
  registration exists unless the domain explicitly says so (the reference
  codebase mints accounts only through authorized internal endpoints).
- Endpoints beyond these three are designed, never improvised.

## 5. Rate limiting — `config/rateLimit.ts`

- **Fixed-window in-memory limiter counting failed attempts** on the auth
  router (so PIN/password guessing cannot be automated); a successful login
  releases its slot so one shared IP cannot lock real users out.
- It throws `ApiError.tooManyRequests()` → the `429 RATE_LIMITED` envelope
  (api-contract.md §4), and adds `Retry-After` from the window reset.
- Stateful by design — a multi-instance deployment swaps the in-memory Map for
  a shared store **without touching the routers** (the same seam idea as
  `config/db.ts`).
- `clearRateLimitStore()` exists as the **test seam**: suites reset it to
  isolate cases (testing.md).

## 6. Env additions — `config/env.ts` (validated once)

```ts
JWT_ACCESS_SECRET: z.string().min(1),
JWT_REFRESH_SECRET: z.string().min(1),   // a different secret from access
JWT_ACCESS_TTL: z.coerce.number(),       // seconds
JWT_REFRESH_TTL: z.coerce.number(),      // seconds
```

## Debt ledger — deviations from this standard recorded, not swept

- **Refresh-in-body (reference codebase)**: `POST /auth/refresh` and
  `/auth/login` currently deliver the refresh token in the response body and
  never set a cookie; clients persist JWTs themselves. Migration per §2 is a
  task of its own: endpoints, cookie parser wiring, CORS `credentials`, tests,
  clients.
- **`ApiError.tooManyRequests`** is called by the limiter but dated from
  before the factory existed in the ApiError spec (api-contract.md §6) — any
  ApiError edit brings the class into conformance.

## Final self-check — run it, don't eyeball it

- [ ] An expired, malformed or tampered token answers the uniform
      `401 { message, code: "UNAUTHORIZED", data: null }` — never a crash, never
      an internal detail
- [ ] A wrong role answers `403 { ..., code: "FORBIDDEN", ... }` with the
      router's declared roles visible in the routes file
- [ ] `POST /auth/refresh` with a valid cookie returns a **new** refresh
      cookie (rotation) + a fresh access token in the body
- [ ] `POST /auth/logout` clears the cookie; a follow-up refresh answers `401`
- [ ] Exceeding the failed-login window answers `429` with
      `{ ..., code: "RATE_LIMITED", ... }` and `Retry-After`
- [ ] No refresh token travels in any response body; no access token is
      stored server-side or client-persisted
