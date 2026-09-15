# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

As this is an unoficial fork, no actual Gems are released for any version.

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
