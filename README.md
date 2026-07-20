# Crypto Price API

A small Rails 8 API that polls [CoinGecko](https://www.coingecko.com/) for the prices of a
fixed watchlist of cryptocurrencies once a minute, caches them, and serves the cached price
from `GET /prices/:symbol`. If CoinGecko is unreachable, the API keeps serving the last price
it successfully fetched instead of erroring out.

## How it works

```
GET /prices/:symbol
      │
      ▼
PricesController#show
      │  reads from Rails.cache (Solid Cache) — never calls CoinGecko itself
      ▼
Rails.cache  (key "crypto_price:<symbol>")
      ▲
      │ overwritten every minute, only on success
FetchCryptoPricesJob  (Solid Queue recurring job, runs every minute)
      │  loops over CryptoPrice::WATCHLIST
      ▼
CoinGecko::Client  (HTTP wrapper: base URL, API key header, timeouts)
      │
      ▼
CoinGecko public API  (GET /simple/price)
```

- **The controller never talks to CoinGecko.** It only reads whatever is currently cached, so
  a request's response time never depends on CoinGecko's uptime or latency.
- **The job is the only writer to the cache.** On a successful fetch it overwrites the cached
  entry for every watchlisted symbol. On failure (timeout, non-2xx response, network error,
  malformed body) it logs a warning and simply *does not* touch the cache — the previously
  cached price is left in place. That's the entire "fallback to last known price" behavior;
  there's no separate fallback code path to reason about.
- **The watchlist is fixed** (`CryptoPrice::WATCHLIST` in `app/models/crypto_price.rb`):
  `bitcoin`, `ethereum`, `dogecoin`, `solana`, `cardano`. `GET /prices/:symbol` only accepts
  CoinGecko coin ids from this list.

## Prerequisites

You need **one** of the following:

- **Ruby 3.3.6** (matches `.ruby-version`), installed via a version manager, e.g.:
  ```bash
  # RVM
  rvm install 3.3.6 && rvm use 3.3.6

  # or rbenv
  rbenv install 3.3.6 && rbenv local 3.3.6
  ```
  SQLite3 is also required (`sqlite3` CLI/dev headers) — on Debian/Ubuntu:
  `sudo apt-get install sqlite3 libsqlite3-dev`.
- **Docker + Docker Compose** — no local Ruby install needed, see [Run with Docker](#run-with-docker).

Either way, you'll need a free CoinGecko "Demo" API key — see below.

## Setup

Requires Ruby 3.3.6 and the gems in the `Gemfile` (Rails 8.1, Solid Cache, Solid Queue —
no Redis needed).

```bash
bundle install
cp .env.example .env        # then fill in CG_API_KEY
bin/rails db:prepare        # creates the primary/cache/queue SQLite databases
```

`CG_API_KEY` is a CoinGecko "Demo" tier key (sent via the `x-cg-demo-api-key` header). Get one
free at https://www.coingecko.com/en/api/pricing.

### Run the app

Two processes are needed: the web server, and the Solid Queue worker that actually runs
`FetchCryptoPricesJob` every minute (see `config/recurring.yml`).

```bash
bin/rails server   # in one terminal
bin/jobs            # in another terminal — runs the Solid Queue supervisor
```

Without `bin/jobs` running, nothing ever populates the cache, so `/prices/:symbol` will keep
returning 404 ("price not available yet").

To fetch immediately instead of waiting up to a minute:

```bash
bin/rails runner 'FetchCryptoPricesJob.perform_now'
```

### Run with Docker

```bash
cp .env.example .env             # fill in CG_API_KEY
echo "RAILS_MASTER_KEY=$(cat config/master.key)" >> .env
docker compose up --build
```

This runs a single container with the web server and the Solid Queue supervisor combined (via
`SOLID_QUEUE_IN_PUMA=true`), so the every-minute job runs automatically. The SQLite databases
are stored in a named Docker volume so cached prices survive container restarts. The API is
then available at `http://localhost:3100` (mapped from the container's port 80; change the
port mapping in `docker-compose.yml` if 3100 is taken).

## API Reference

### `GET /prices/:symbol`

`:symbol` must be a CoinGecko coin id from the watchlist:
`bitcoin`, `ethereum`, `dogecoin`, `solana`, `cardano` (`CryptoPrice::WATCHLIST` in
`app/models/crypto_price.rb` — see [Adding a coin](#adding-a-coin-to-the-watchlist) to extend
it). Prices are always in USD.

**200 OK** — the symbol is on the watchlist and a price has been cached at least once:

```bash
curl http://localhost:3000/prices/bitcoin
```
```json
{
  "symbol": "bitcoin",
  "price": 67000.12,
  "currency": "usd",
  "fetched_at": "2026-07-20T10:00:00.000Z"
}
```

`fetched_at` is the timestamp of the last *successful* CoinGecko fetch — during an outage this
stays fixed while `FetchCryptoPricesJob` keeps failing and falling back, so a client can tell
how stale the price is.

**404 Not Found — unknown symbol** — `:symbol` isn't on the watchlist:

```bash
curl http://localhost:3000/prices/not-a-real-coin
```
```json
{ "error": "unknown symbol" }
```

**404 Not Found — not fetched yet** — `:symbol` is valid but the background job hasn't
successfully cached a price for it yet (e.g. right after first boot, before `bin/jobs` /
Solid Queue has run):

```bash
curl http://localhost:3000/prices/cardano
```
```json
{ "error": "price not available yet" }
```

### Adding a coin to the watchlist

Add the CoinGecko coin id to `CryptoPrice::WATCHLIST` in `app/models/crypto_price.rb` (find
ids via CoinGecko's `/coins/list` endpoint or a coin's CoinGecko URL slug). It'll be picked up
by the next `FetchCryptoPricesJob` run — no restart or migration required.

## Tests

```bash
bundle exec rspec
```

Covers:
- `spec/services/coin_gecko/client_spec.rb` — the HTTP client (success, non-2xx, timeout,
  unparsable body, correct headers).
- `spec/jobs/fetch_crypto_prices_job_spec.rb` — **job logic** (writes every watchlisted
  symbol on success) and **fallback logic** (a failed fetch leaves the cache untouched and
  does not raise).
- `spec/models/crypto_price_spec.rb` — **caching behavior** (read/write round-trip, per-symbol
  isolation, overwrite-on-refresh, cache key format).
- `spec/requests/prices_spec.rb` — the HTTP endpoint (200 with cached data, 404 for an unknown
  symbol, 404 when a known symbol has no cached value yet, and that no real HTTP call is ever
  made from the request path).

All CoinGecko HTTP calls are stubbed with WebMock; `WebMock.disable_net_connect!` is enabled
globally in `spec/rails_helper.rb` so a test can never accidentally hit the real API.

## Troubleshooting

**`/prices/:symbol` always returns `{"error":"price not available yet"}`**
Nothing has populated the cache yet. Either wait up to a minute for the recurring job (make
sure `bin/jobs` is running locally, or that the container logs show a `SolidQueue ... Started
Scheduler` line), or trigger a fetch immediately:
```bash
bin/rails runner 'FetchCryptoPricesJob.perform_now'
```

**Job logs `CoinGecko fetch failed` / prices never update**
`CG_API_KEY` is missing, wrong, or CoinGecko is unreachable. Check `.env` (local) or the
container's environment (`docker compose exec api env | grep CG_API_KEY`). This is also the
expected fallback path — old cached prices keep being served rather than the endpoint erroring.

**`bin/rails db:prepare` errors with "no such table"**
The primary/cache/queue SQLite databases are out of sync. Re-run `bin/rails db:prepare` for
the affected `RAILS_ENV` (e.g. `RAILS_ENV=test bin/rails db:prepare`); it's safe to re-run.

**`docker compose up` fails with "address already in use"**
Something else on your machine is already using the host port in `docker-compose.yml`
(`3100:80` by default). Change the left-hand port, e.g. `"3200:80"`, and re-run.

**`docker compose up` fails with a master key / credentials error**
`RAILS_MASTER_KEY` wasn't passed to the container. Make sure `.env` has a
`RAILS_MASTER_KEY=...` line (`echo "RAILS_MASTER_KEY=$(cat config/master.key)" >> .env`) —
`config/master.key` itself is gitignored and intentionally excluded from the image.

**RSpec run hits errors about `solid_cache`/`solid_queue` tables, or a stale env**
Check `RAILS_ENV` isn't already set to something unexpected in your shell (`echo
$RAILS_ENV`) — it overrides RSpec's own `test` default. Run with it forced explicitly if
needed: `RAILS_ENV=test bundle exec rspec`.
