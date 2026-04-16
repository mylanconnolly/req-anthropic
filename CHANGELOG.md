# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0]

### Added

- `ReqAnthropic.RateLimit` struct — parsed from `anthropic-ratelimit-requests-remaining`,
  `anthropic-ratelimit-tokens-remaining`, and `retry-after` headers on every
  response. Access it on successful responses via `ReqAnthropic.rate_limit/1`.
- `ReqAnthropic.RateLimited` exception — returned as
  `{:error, %RateLimited{retry_after: n}}` when the API responds with
  HTTP 429. The `retry_after` field (seconds) is promoted to the top level
  for ergonomic pattern matching.
- `ReqAnthropic.rate_limit/1` — extracts the `%RateLimit{}` from a
  `%Req.Response{}`'s private data.
- `ReqAnthropic.Error` now carries a `:rate_limit` field
  (`%RateLimit{} | nil`) populated from response headers on all non-2xx
  errors.

### Changed

- **Breaking:** HTTP 429 responses now return
  `{:error, %ReqAnthropic.RateLimited{}}` instead of
  `{:error, %ReqAnthropic.Error{type: "rate_limit_error"}}`. Callers that
  pattern-match on `%Error{status: 429}` or `%Error{type: "rate_limit_error"}`
  should update to match `%RateLimited{}`. The catch-all
  `{:error, exception}` pattern is unaffected.

## [0.1.1]

### Fixed

- Fixed base URL not being applied to requests. The `auth_step` was
  appended after Req's built-in `put_base_url` step, so relative paths
  like `/v1/messages` were sent to Finch without a scheme, producing
  `ArgumentError: scheme is required for url`. The step is now prepended
  so the base URL is set before Req resolves it.
- Set a default `receive_timeout` of 120 seconds in `Client.build/1`.
  Finch's 15-second default was too short for LLM API calls, causing
  `Req.TransportError` (`:closed`) on longer requests.

### Added

- `Tools.custom/1` now accepts an optional `:function` (1-arity) that
  `Messages.run/1` will call automatically when the model invokes the
  tool.
- `Tools.function_map/1` — builds a `%{name => function}` lookup from a
  list of tool maps.
- `Messages.run/1` — sends a message and automatically executes tool
  calls that have a registered `:function`, looping until the model
  produces a final response. Accepts `:max_rounds` (default 10) to cap
  the number of round-trips.

## [0.1.0]

Initial release.

### Added

- `ReqAnthropic.attach/2` plugin layer for use with any `%Req.Request{}`,
  with auth headers, base URL handling, error normalization, and beta
  header merging.
- `ReqAnthropic.Client.build/1` shared builder used by every resource
  module.
- API key resolution from call-site option, application environment, or
  the `ANTHROPIC_API_KEY` environment variable, with `ReqAnthropic.AuthError`
  raised when none are configured.
- `ReqAnthropic.Messages` — `create/1`, `count_tokens/1`, plus streaming
  via `stream/1`, `text_deltas/1`, and `collect/1`.
- `ReqAnthropic.SSE.parse_stream/1` — buffered Server-Sent Events parser
  that handles cross-chunk event boundaries, ping events, and multi-line
  `data:` payloads.
- `ReqAnthropic.Models` — `list/1`, `get/2`, `capabilities/1`,
  `clear_cache/0`, with results cached in an ETS table owned by the
  application supervisor.
- `ReqAnthropic.Model` and `ReqAnthropic.Model.Capabilities` structs,
  including a static capability table for known Claude 4 models.
- `ReqAnthropic.Batches` — `create/1`, `get/2`, `list/1`, `cancel/2`,
  `delete/2`, and `results/2` with JSONL streaming.
- `ReqAnthropic.Files` — `create/1` (multipart upload), `list/1`,
  `get/2`, `delete/2`, and `content/2`. The `files-api-2025-04-14` beta
  header is added automatically.
- `ReqAnthropic.Tools` — builders for `web_search/1`, `web_fetch/1`,
  `bash/1`, `text_editor/1`, `computer/1`, `memory/1`, `advisor/1`, and
  `custom/1`. Tools that require a beta header tag themselves so the
  resource module can wire it up.
- `ReqAnthropic.Beta` — helpers for normalizing, deduping, and merging
  the `anthropic-beta` header value.
- `ReqAnthropic.Error` and `ReqAnthropic.AuthError` exception structs.
- `ReqAnthropic.Agents` — full CRUD against `/v1/agents`, gated behind
  the `managed-agents-2026-04-01` beta header.
- `ReqAnthropic.Environments` — full CRUD against `/v1/environments`.
- `ReqAnthropic.Sessions` — `create/1`, `get/2`, `list/1`, `archive/2`,
  `delete/2`, `send_events/3`, `send_message/3`, `interrupt/2`, `events/2`,
  and `stream/2` for the SSE event stream.
- `ReqAnthropic.Vaults` — full CRUD plus `archive/2`.
- `ReqAnthropic.Vaults.Credentials` — nested CRUD plus `archive/3`.
- `ReqAnthropic.Conversation` — client-side multi-turn helper that holds
  message history and default request options for repeated `Messages`
  calls.

[Unreleased]: https://github.com/mylanconnolly/req_anthropic/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/mylanconnolly/req_anthropic/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/mylanconnolly/req_anthropic/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mylanconnolly/req_anthropic/releases/tag/v0.1.0
