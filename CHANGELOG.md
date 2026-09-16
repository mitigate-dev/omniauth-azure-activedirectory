# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

As this is an unofficial fork, no actual Gems are released for any version.

## [1.4.0] - 2026-09-16

### Added
- Pluggable nonce storage. `nonce_store` takes a class instantiated with the
  strategy (mirroring `tenant_provider`), defaulting to
  `SessionNonceStore` — the existing behaviour, session key and
  `nonce_max_count` cap all unchanged.
- `CacheNonceStore`, which keeps nonces in an injected cache rather than the
  session. Azure returns the id_token via a cross-site `form_post`, and a
  `SameSite=Lax` session cookie is not sent on a cross-site POST, so the
  session-stored nonce is unreachable at the callback and every login fails
  with 'Returned nonce did not match.'. Also fixes nonce loss across
  application servers without sticky sessions.
- `nonce_cache` and `nonce_ttl` options for `CacheNonceStore`. The cache is any
  object responding to `#read`, `#write(key, value, expires_in:)` and
  `#delete`; the gem gains no Rails dependency.
- `nonce_store` accepts a String or Symbol naming the class, or a callable,
  resolved per request instead of when the provider is declared. A bare Class
  constant must be loaded before the initializer that declares the provider,
  which rules out anything autoloadable under `app/`.
- `payload`/`on_claim` hooks so a store subclass can carry state across the
  callback that the session cannot hold.
- `nonce_logger` option. Both stores log claim misses with the reason, which
  the user-facing 'Returned nonce did not match' cannot convey.
- README section on nonce storage, including the non-atomic claim.

### Fixed
- `CacheNonceStore` converts a raising cache into the same `OmniAuth::Error` it
  raises for a rejected write, keeping the original as `cause`. Caches differ in
  what they rescue: `redis-activesupport` rescues only
  `Redis::BaseConnectionError` (and re-raises even that under `raise_errors?`),
  while Rails' `RedisCacheStore` also swallows `Redis::BaseError`. A Redis OOM
  therefore escaped the write guard entirely on some hosts and reached the
  application as a bare `Redis::CommandError` that no `rescue_from
  OmniAuth::Error` would catch. A failed cache read is also distinguished from a
  nonce miss, and a failed delete no longer refuses an otherwise valid login.

### Changed
- `new_nonce` and `check_nonce` delegate to the configured store instead of
  manipulating the session directly. Behaviour under the default store is
  unchanged; `check_nonce` now returns a boolean rather than the removed nonce.

## [1.3.0] - 2026-09-15

### Added
- Declare `base64` as a runtime dependency. Ruby 3.4 moved `base64` from the
  default gems to the bundled gems, so under Bundler it is unavailable unless
  declared. Without this, `jwt` 2.2.x fails to load entirely on Ruby 3.4.
- Explicitly `require` the stdlib the strategy actually uses (`base64`, `json`,
  `net/http`, `uri`). These were previously reached only via transitive requires
  from `omniauth`/`jwt`.
- Declare `required_ruby_version = '>= 2.4'`. The floor was previously implicit;
  `base64` imposes it, and it is the highest among the required dependencies.
- README section on starting the request phase, covering the OmniAuth 2 POST-only
  default, `omniauth-rails_csrf_protection`, the interstitial needed when a
  framework redirects into the sign-in path, and why re-enabling GET reintroduces
  CVE-2015-9284.

### Changed
- Relax `jwt` constraint to `>= 2.2, < 3`.
- Relax `omniauth` constraint to `>= 1.1, < 3`, adding OmniAuth 2
  support.
- Update development dependencies `rake` (`~> 13.0`) and `webmock`
  (`~> 3.0`).

### Fixed
- Stub `:path` on the request double in the specs. OmniAuth 2 calls
  `request.path`, which the original 2015-era double did not respond to.

## [1.2.0] - 2020-03-19

### Added
- `nonce_max_count` option (default 10), bounding how many in-flight nonces a
  session retains before the oldest is dropped.

### Changed
- Request the `openid profile` scope instead of `openid`. The `profile` scope is
  required for the name claims that populate `info` in the auth hash.
- `jwt` runtime dependency `~> 2.0` -> `~> 2.2.0`, adapting to the jwt 2.2 API
  rename: `JWT::Decode.base64url_decode` -> `JWT::Base64.url_decode`, and
  `JWT::Encode.base64url_encode` -> `JWT::Base64.url_encode`.
- `webmock` development dependency `~> 1.21` -> `~> 2.3`.

### Removed
- `read_nonce`, superseded by `check_nonce(nonce)`.

### Fixed
- Logins started in more than one browser tab. Each request phase used to
  overwrite the session's single nonce, so only the most recently opened tab
  could complete authentication and the rest failed with 'Returned nonce did not
  match.'. Nonces are now held as an array under the session key
  `omniauth-azure-activedirectory.nonces` (previously a single value under
  `omniauth-azure-activedirectory.nonce`) and are matched and removed anywhere in
  that array.

  Note for anyone overriding the strategy: both the session key and the method
  name changed, so patches written against `read_nonce` or the singular key need
  updating.

## [1.1.0] - 2019-01-05

### Added
- Support for the Azure v2.0 AD openidconnect endpoint
- option to run a single provider for multiple AD tenants
- support for password reset requests

### Changed
- Updated JWT dependency to ~> 2.0

### Fixed
- use a configured on\_failure error handler instead of always raising
  exceptions in callback\_phase
