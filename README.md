# ReqAnthropic

[![Hex.pm](https://img.shields.io/hexpm/v/req_anthropic.svg)](https://hex.pm/packages/req_anthropic)
[![Documentation](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/req_anthropic)

An Anthropic-focused API client for Elixir, built on [Req](https://hex.pm/packages/req).

`req_anthropic` is laser-focused on the Claude API. Because it isn't trying to
be a generic LLM abstraction, it can expose Anthropic-specific features
directly — beta headers, streaming, batches, files, the full managed-agents
surface (agents, environments, sessions, vaults), and first-class tool
builders for web search, web fetch, advisor, memory, bash, computer use,
and the text editor.

You get two layers in one package:

- A **plugin layer** (`ReqAnthropic.attach/2`) you can drop on any
  `%Req.Request{}` for full control.
- A **resource layer** (`ReqAnthropic.Messages`, `ReqAnthropic.Models`,
  `ReqAnthropic.Sessions`, …) for ergonomic, no-boilerplate calls.

## Installation

Add `req_anthropic` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:req_anthropic, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get`.

## Authentication

The API key is resolved at request time, in this order:

1. The `:api_key` option passed at the call site.
2. `Application.get_env(:req_anthropic, :api_key)`.
3. The `ANTHROPIC_API_KEY` environment variable.

If none are set, `ReqAnthropic.AuthError` is raised before the request is sent.

```elixir
# config/runtime.exs
import Config

config :req_anthropic,
  api_key: System.fetch_env!("ANTHROPIC_API_KEY")
```

Or override per-call:

```elixir
ReqAnthropic.Messages.create(
  model: "claude-haiku-4-5",
  max_tokens: 256,
  messages: [%{role: "user", content: "ping"}],
  api_key: "sk-ant-..."
)
```

## Quick start

### Send a message

```elixir
{:ok, message} =
  ReqAnthropic.Messages.create(
    model: "claude-haiku-4-5",
    max_tokens: 1024,
    messages: [%{role: "user", content: "Explain Elixir in one sentence."}]
  )

[%{"text" => text}] = message["content"]
IO.puts(text)
```

### Stream a response

`stream/1` returns a `Stream` of decoded SSE events. `text_deltas/1` flattens
those events to text chunks; `collect/1` reassembles them into the same shape
`create/1` returns.

```elixir
{:ok, stream} =
  ReqAnthropic.Messages.stream(
    model: "claude-sonnet-4-6",
    max_tokens: 1024,
    messages: [%{role: "user", content: "Write a haiku about BEAM."}]
  )

stream
|> ReqAnthropic.Messages.text_deltas()
|> Enum.each(&IO.write/1)
```

Or get the full assistant message back:

```elixir
{:ok, stream} = ReqAnthropic.Messages.stream(model: "...", max_tokens: 1024, messages: [...])
{:ok, message} = ReqAnthropic.Messages.collect(stream)
```

### Count tokens

```elixir
{:ok, %{"input_tokens" => n}} =
  ReqAnthropic.Messages.count_tokens(
    model: "claude-haiku-4-5",
    messages: [%{role: "user", content: "How many tokens is this?"}]
  )
```

### List and inspect models

Results are cached in ETS (default TTL: 1 hour). Pass `cache: false` to bypass.

```elixir
{:ok, models} = ReqAnthropic.Models.list()
{:ok, model}  = ReqAnthropic.Models.get("claude-opus-4-6")

caps = ReqAnthropic.Models.capabilities("claude-opus-4-6")
caps.supports_vision         #=> true
caps.supports_computer_use   #=> true
caps.max_input_tokens        #=> 200_000
```

### Tools

Tool builders return ready-to-send maps. Tools that require a beta header
flag themselves so the resource module can wire it up.

```elixir
alias ReqAnthropic.Tools

tools = [
  Tools.web_search(max_uses: 5),
  Tools.web_fetch(),
  Tools.bash(),
  Tools.text_editor(),
  Tools.custom(
    name: "get_weather",
    description: "Look up the weather for a city.",
    input_schema: %{
      type: "object",
      properties: %{city: %{type: "string"}},
      required: ["city"]
    }
  )
]

ReqAnthropic.Messages.create(
  model: "claude-sonnet-4-6",
  max_tokens: 1024,
  tools: tools,
  messages: [%{role: "user", content: "What's the weather in Tokyo?"}]
)
```

Available builders: `web_search/1`, `web_fetch/1`, `bash/1`, `text_editor/1`,
`computer/1`, `memory/1`, `advisor/1`, `custom/1`.

### Files

The Files API is a beta endpoint; the `files-api-2025-04-14` header is added
automatically.

```elixir
{:ok, file}  = ReqAnthropic.Files.create(path: "report.pdf")
{:ok, list}  = ReqAnthropic.Files.list()
{:ok, info}  = ReqAnthropic.Files.get(file["id"])
{:ok, bytes} = ReqAnthropic.Files.content(file["id"])
{:ok, _}     = ReqAnthropic.Files.delete(file["id"])
```

### Message Batches

```elixir
{:ok, batch} =
  ReqAnthropic.Batches.create(
    requests: [
      %{
        custom_id: "req-1",
        params: %{
          model: "claude-haiku-4-5",
          max_tokens: 256,
          messages: [%{role: "user", content: "Hello!"}]
        }
      }
    ]
  )

{:ok, status} = ReqAnthropic.Batches.get(batch["id"])

# When complete, stream the JSONL results:
{:ok, stream} = ReqAnthropic.Batches.results(batch["id"])
Enum.each(stream, &IO.inspect/1)
```

### Multi-turn conversations

`ReqAnthropic.Conversation` is a small client-side helper that keeps message
history and default request options so you don't rebuild the payload yourself.
The Anthropic API itself remains stateless.

```elixir
alias ReqAnthropic.Conversation

convo =
  Conversation.new(
    model: "claude-haiku-4-5",
    max_tokens: 512,
    system: "You are concise."
  )
  |> Conversation.user("Tell me about Elixir.")

{:ok, convo} = Conversation.send(convo)
IO.puts(Conversation.last_text(convo))

convo = Conversation.user(convo, "What about OTP?")
{:ok, convo} = Conversation.send(convo)
```

## Managed Agents

The full managed-agents API surface is supported. The
`managed-agents-2026-04-01` beta header is added automatically.

### Agents and environments

```elixir
{:ok, agent} =
  ReqAnthropic.Agents.create(
    model: "claude-sonnet-4-6",
    name: "Repo assistant",
    system: "You help users navigate code repositories."
  )

{:ok, env} =
  ReqAnthropic.Environments.create(
    name: "python-env",
    config: %{
      type: "cloud",
      packages: %{pip: ["pandas", "numpy"]},
      networking: %{type: "limited", allow_package_managers: true}
    }
  )
```

### Sessions

```elixir
alias ReqAnthropic.Sessions

{:ok, session} = Sessions.create(agent: agent["id"], environment_id: env["id"])

# Kick off work
{:ok, _} = Sessions.send_message(session["id"], "List the files in /workspace")

# Stream the agent's activity
{:ok, stream} = Sessions.stream(session["id"])

stream
|> Stream.each(&IO.inspect/1)
|> Enum.take(20)

# Steer or interrupt mid-execution
Sessions.interrupt(session["id"], message: "Actually, focus on README.md")

# Fetch historical events
{:ok, %{"data" => events}} = Sessions.events(session["id"], limit: 50)

# Tear down
Sessions.archive(session["id"])
```

`Sessions.send_events/3` accepts the full event vocabulary if you need to
emit `user.custom_tool_result`, `user.tool_confirmation`, or
`user.define_outcome` events directly.

### Vaults and credentials

Vaults store per-user MCP credentials so you don't have to run your own
secret store.

```elixir
alias ReqAnthropic.{Vaults, Vaults.Credentials}

{:ok, vault} = Vaults.create(display_name: "Alice")

{:ok, _cred} =
  Credentials.create(vault["id"],
    display_name: "Alice's Slack",
    auth: %{
      type: "static_bearer",
      mcp_server_url: "https://mcp.slack.com/mcp",
      token: "xoxp-..."
    }
  )

# Reference the vault when starting a session:
{:ok, session} =
  ReqAnthropic.Sessions.create(
    agent: agent["id"],
    environment_id: env["id"],
    vault_ids: [vault["id"]]
  )
```

## Plugin layer

If you'd rather build the request yourself, attach the plugin to any Req
struct. The same auth, error normalization, and base-URL handling apply.

```elixir
req =
  Req.new()
  |> ReqAnthropic.attach(api_key: "sk-ant-...", beta: ["prompt-caching-2024-07-31"])

{:ok, response} =
  Req.post(req,
    url: "/v1/messages",
    json: %{
      model: "claude-haiku-4-5",
      max_tokens: 256,
      messages: [%{role: "user", content: "ping"}]
    }
  )
```

## Error handling

Non-2xx responses are normalized into `%ReqAnthropic.Error{}`:

```elixir
case ReqAnthropic.Messages.create(...) do
  {:ok, message} ->
    handle(message)

  {:error, %ReqAnthropic.Error{type: "rate_limit_error", request_id: id}} ->
    Logger.warning("Rate limited (request #{id}); backing off")

  {:error, %ReqAnthropic.Error{} = err} ->
    Logger.error("API error: #{Exception.message(err)}")
end
```

Bang variants (`create!/1`, `get!/2`, …) are available where it makes sense
and raise `ReqAnthropic.Error` directly.

## Configuration reference

```elixir
config :req_anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  base_url: "https://api.anthropic.com",
  anthropic_version: "2023-06-01",
  beta: [],
  models_cache_ttl: :timer.hours(1)
```

Every key is also accepted as a per-call option. Anything else you want to
pass through to Req goes under `:req_options`:

```elixir
ReqAnthropic.Messages.create(
  model: "claude-sonnet-4-6",
  max_tokens: 1024,
  messages: [...],
  req_options: [receive_timeout: 60_000, retry: :transient]
)
```

## Testing your code

Resource calls go through `Req`, so you can use [`Req.Test`](https://hexdocs.pm/req/Req.Test.html)
plug stubs in your own tests:

```elixir
# config/test.exs
config :req_anthropic,
  api_key: "test-key",
  plug: {Req.Test, MyApp.AnthropicStub}

# test/some_test.exs
test "summarizes input" do
  Req.Test.stub(MyApp.AnthropicStub, fn conn ->
    Req.Test.json(conn, %{
      "id" => "msg_1",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => "summary"}]
    })
  end)

  assert {:ok, _} = MyApp.summarize("...")
end
```

## License

MIT
