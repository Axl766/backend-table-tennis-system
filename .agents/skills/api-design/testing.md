# Testing Standard

How code in this stack is tested: **vitest as the only runner**, two levels
(unit, integration), and the plain-HTTP harness the integration tests speak
through. Driven inside the `/tdd` loop — one red-green slice at a time.

> Applies to all code this standard touches (SKILL.md §Compliance). Known
> deviations live in the **Debt** section at the bottom — bring touched code into
> conformance; record found-but-unfixed deviations there.

## 1. Runner — vitest, one and only

- Scripts: `"test": "vitest run"` and `"test:watch": "vitest"`. Zero-config
  start: vitest picks up `*.test.ts` under `tests/` and colocated files.
- Every test file is TypeScript ESM with the same `.js` import suffix rule as
  the source (conventions.md §3).
- `pnpm test` green is an exit criterion wherever a build or resource
  checklist demands it (bootstrap.md, new-resource.md).

## 2. Two levels — and where each concerns

| Level | What it tests | Server? | DB? |
|---|---|---|---|
| **Unit** | Pure logic: algorithms, `signToken`/`verifyToken`, computed payloads (the service's pure statics, conventions.md §5.1) | No | No |
| **Integration** | The HTTP surface: status codes, envelope shapes, role rules, persistence — **external behavior only** | Real app on an ephemeral port | **Real** test DB via `prisma` |

- There is **no third "supertest" level**: the harness already speaks plain
  HTTP exactly as a client does — same work, zero extra dependency, one style.
- Browser E2E (a tool driving a real UI) is a **separate concern** — never part
  of this standard.
- Assertions target **public behavior**: status + envelope
  (`message` / `code` / `data` / `errors`) and role rules — never hashing or
  token internals, never ORM internals.

## 3. The harness — `tests/helpers/harness.ts`

The suite boots the **real app** once and speaks plain HTTP through a tiny
client. Distilled shape:

```ts
import http from "node:http";
import { app } from "../../src/server.js";

export const startTestServer = async (): Promise<void> => {
  // http.createServer(app) on an ephemeral port — not a MOCK server:
  // every request crosses the full middleware stack, exactly like prod.
};

export const request = async (
  method: string,
  path: string,
  options: { token?: string; body?: unknown; cookie?: string } = {},
): Promise<ApiResponse> => {
  // plain fetch against 127.0.0.1:<ephemeral-port>; Bearer token from
  // options.token; sends options.cookie as the Cookie header when present.
};

export type ApiResponse = {
  status: number;
  // body typed loosely; assertions read message/code/data/errors by shape
};
```

- **Cookie support** (the refresh-cookie flow of auth.md): after a
  `Set-Cookie` response, read it with
  `response.headers.getSetCookie()` and send it back on the next
  `request(...)` through the `cookie` option — the helper never parses cookie
  semantics, it only carries them.
- **Fixtures own their rows**: suite-level `before` creates users/rows through
  the API or direct prisma; `after` cleans them up in reverse-dependency order
  (fixtures guarded by `RESTRICT`-style relations go first). Suites must be
  independently runnable.
- **Reset seams**: process-global state exposes an explicit reset hook the
  harness re-exports — e.g. the rate limiter's store is reset per test
  isolation so suites never fight over the `/auth` budget.
- **DB**: tests run against the `DATABASE_URL` the env seam resolves — a
  disposable test database; no global seed dependency, no cross-suite
  assumptions.

## 4. An integration case reads like this

```ts
describe("Accounts", () => {
  before(async () => {
    await startTestServer();
    // fixtures: admin ensured, users created, tokens minted by logging in
  });

  it("admin creates an account; duplicate username answers 409", async () => {
    const created = await request("POST", "/api/v1/accounts", {
      token: adminToken,
      body: { role: "JUDGE_GENERAL", username: uniqueUsername() },
    });
    assert.equal(created.status, 201);
    assert.match(created.body.message as string, /^Account created successfully$/);

    const duplicate = await request("POST", "/api/v1/accounts", {
      token: adminToken,
      body: { role: "JUDGE_GENERAL", username: created.body.data?.username },
    });
    assert.equal(duplicate.status, 409);
    assert.equal(duplicate.body.code, "CONFLICT");
  });

  after(async () => { /* reverse-order cleanup, closeTestServer, prisma.$disconnect */ });
});
```

- One behavior per `it` — each case reads as one red-green slice.
- The refresh-cookie flow asserts **rotation**: a refresh call must deliver a
  **changed** `Set-Cookie`, and logout must clear it (auth.md self-check).

## Debt ledger — deviations from this standard recorded, not swept

- The six existing suites (`tests/*.test.ts`) run on **`node:test`**
  (`tsx --test`) — the runner predates this standard. Migration to vitest is a
  task of its own (suites are runner-agnostic; only the
  `describe`/`it`/`assert` imports change).
- Until the migration lands, the two runners must never be mixed inside one
  suite; the vitest-only scripts above are the target state.

## Final self-check — run it, don't eyeball it

- [ ] `pnpm test` green; each suite also green when run **individually** (no
      cross-suite coupling)
- [ ] Removing an envelope assertion makes the suite fail (the suite is
      actually checking the contract, not just wiring)
- [ ] No test reads module internals (private helpers, ORM payloads); all go
      through the public surface (`request(...)`, exported pure functions)
- [ ] Fixtures clean up after themselves; running the suite twice in a row
      passes both times
