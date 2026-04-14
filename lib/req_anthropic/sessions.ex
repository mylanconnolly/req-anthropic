defmodule ReqAnthropic.Sessions do
  @moduledoc """
  The Managed Agents Sessions API: run stateful agent sessions against an
  environment. Covers session lifecycle, event submission, event history,
  and the SSE event stream.

  A session is event-driven:

    * Create the session with `create/1`, giving it an agent id and an
      environment id.
    * Send a `user.message` via `send_events/3` to start work.
    * Stream the agent's activity back with `stream/2`, which yields
      parsed session/agent/span events.
    * Steer or interrupt in-flight with additional `send_events/3` calls,
      typically `user.interrupt` or `user.tool_confirmation`.

  ## Example

      {:ok, session} =
        ReqAnthropic.Sessions.create(
          agent: "agent_01ABC...",
          environment_id: "env_01DEF..."
        )

      {:ok, _} =
        ReqAnthropic.Sessions.send_events(session["id"], [
          %{type: "user.message", content: [%{type: "text", text: "List files"}]}
        ])

      {:ok, stream} = ReqAnthropic.Sessions.stream(session["id"])
      stream |> Enum.take(10) |> IO.inspect()
  """

  alias ReqAnthropic.{Beta, Client, Error, SSE}

  @path "/v1/sessions"
  @beta "managed-agents-2026-04-01"

  @spec create(keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def create(opts) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.post(url: @path, json: payload)
    |> handle()
  end

  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def get(id, opts \\ []) when is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id)
    |> handle()
  end

  @spec list(keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def list(opts \\ []) do
    {query, opts} =
      Keyword.split(opts, [
        :agent_id,
        :agent_version,
        :include_archived,
        :limit,
        :order,
        :page
      ])

    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: @path, params: query)
    |> handle()
  end

  @doc "Archive a session. Preserves history but blocks future events."
  @spec archive(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def archive(id, opts \\ []) when is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.post(url: @path <> "/" <> id <> "/archive")
    |> handle()
  end

  @doc "Delete a session permanently. Cannot be called while the session is running."
  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def delete(id, opts \\ []) when is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.delete(url: @path <> "/" <> id)
    |> handle()
  end

  @doc """
  Send one or more events to a session. `events` is a list of event maps
  (`user.message`, `user.interrupt`, `user.custom_tool_result`,
  `user.tool_confirmation`, `user.define_outcome`).
  """
  @spec send_events(String.t(), [map()], keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def send_events(id, events, opts \\ []) when is_binary(id) and is_list(events) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.post(url: @path <> "/" <> id <> "/events", json: %{events: events})
    |> handle()
  end

  @doc """
  Convenience: send a single user text message.
  """
  @spec send_message(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def send_message(id, text, opts \\ []) when is_binary(id) and is_binary(text) do
    send_events(
      id,
      [%{type: "user.message", content: [%{type: "text", text: text}]}],
      opts
    )
  end

  @doc """
  Convenience: send an interrupt, optionally with a follow-up message.
  """
  @spec interrupt(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def interrupt(id, opts \\ []) when is_binary(id) do
    {message, opts} = Keyword.pop(opts, :message)

    events =
      case message do
        nil ->
          [%{type: "user.interrupt"}]

        text when is_binary(text) ->
          [
            %{type: "user.interrupt"},
            %{type: "user.message", content: [%{type: "text", text: text}]}
          ]
      end

    send_events(id, events, opts)
  end

  @doc """
  List historical events for a session (paginated).
  """
  @spec events(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def events(id, opts \\ []) when is_binary(id) do
    {query, opts} = Keyword.split(opts, [:limit, :order, :page, :after_id, :before_id])

    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id <> "/events", params: query)
    |> handle()
  end

  @doc """
  Open an SSE stream for a session and return `{:ok, stream}` where
  `stream` yields parsed event maps. Must be consumed in the calling
  process (per Req's `into: :self` contract).
  """
  @spec stream(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(id, opts \\ []) when is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id <> "/stream", into: :self)
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body |> chunks() |> SSE.parse_stream()}

      {:ok, %Req.Response{} = resp} ->
        {:error, Error.from_response(resp)}

      {:error, %Error{} = err} ->
        {:error, err}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp chunks(%Req.Response.Async{} = async), do: async
  defp chunks(binary) when is_binary(binary), do: [binary]
  defp chunks(list) when is_list(list), do: list

  defp split(opts) do
    {client_opts, rest} = ReqAnthropic.split_client_opts(opts)
    {client_opts, Map.new(rest)}
  end

  defp handle({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp handle({:ok, %Req.Response{} = resp}), do: {:error, Error.from_response(resp)}
  defp handle({:error, %Error{} = err}), do: {:error, err}
  defp handle({:error, exception}), do: {:error, exception}
end
