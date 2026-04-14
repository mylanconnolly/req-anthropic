defmodule ReqAnthropic.Messages do
  @moduledoc """
  The Messages API: send prompts to Claude, count tokens, and stream
  responses as parsed events.

      ReqAnthropic.Messages.create(
        model: "claude-haiku-4-5",
        max_tokens: 256,
        messages: [%{role: "user", content: "Hello"}]
      )

  Streaming returns a `Stream` of decoded events. Convenience helpers are
  provided for common patterns:

      {:ok, stream} = ReqAnthropic.Messages.stream(model: "...", ...)
      stream |> ReqAnthropic.Messages.text_deltas() |> Enum.each(&IO.write/1)
  """

  alias ReqAnthropic.{Client, Error, SSE}

  @path "/v1/messages"
  @count_path "/v1/messages/count_tokens"

  @doc """
  Create a non-streaming message.

  All Anthropic Messages parameters are passed through as-is. Pulled out of
  the keyword for client configuration are: `:api_key`, `:base_url`,
  `:anthropic_version`, `:beta`, `:req_options`.
  """
  @spec create(keyword() | map()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def create(opts) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Client.build()
    |> Req.post(url: @path, json: payload)
    |> handle_response()
  end

  @doc "Same as `create/1`, but raises on error."
  @spec create!(keyword() | map()) :: map()
  def create!(opts) do
    case create(opts) do
      {:ok, body} -> body
      {:error, error} -> raise error
    end
  end

  @doc """
  Stream a message response. Returns `{:ok, stream}` where `stream` is a
  lazy enumerable of decoded SSE events. The stream MUST be consumed in the
  same process that called `stream/1` (a Req requirement of `into: :self`).
  """
  @spec stream(keyword() | map()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(opts) do
    {client_opts, payload} = split(opts)
    payload = Map.put(payload, :stream, true)

    client_opts
    |> Client.build()
    |> Req.post(url: @path, json: payload, into: :self)
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body |> chunks() |> SSE.parse_stream()}

      {:ok, %Req.Response{} = resp} ->
        {:error, Error.from_response(resp)}

      {:error, %Error{}} = err ->
        err

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Stream a message response and yield only text deltas as strings. Useful
  for piping straight to `IO.write/1` or building up a final string.
  """
  @spec text_deltas(Enumerable.t()) :: Enumerable.t()
  def text_deltas(stream) do
    Stream.flat_map(stream, fn
      %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}} ->
        [text]

      _ ->
        []
    end)
  end

  @doc """
  Drain a streamed response into the same shape that `create/1` would
  return, by reassembling content blocks from their deltas.
  """
  @spec collect(Enumerable.t()) :: {:ok, map()} | {:error, Error.t()}
  def collect(stream) do
    Enum.reduce_while(stream, %{message: nil, blocks: %{}, stop: nil}, fn
      {:error, %Error{} = err}, _acc ->
        {:halt, {:error, err}}

      %{"type" => "message_start", "message" => message}, acc ->
        {:cont, %{acc | message: message}}

      %{"type" => "content_block_start", "index" => idx, "content_block" => block}, acc ->
        {:cont, put_in(acc.blocks[idx], block)}

      %{"type" => "content_block_delta", "index" => idx, "delta" => delta}, acc ->
        {:cont, update_in(acc.blocks[idx], &apply_delta(&1, delta))}

      %{"type" => "content_block_stop"}, acc ->
        {:cont, acc}

      %{"type" => "message_delta", "delta" => delta} = ev, acc ->
        usage = Map.get(ev, "usage")
        message = acc.message |> Map.merge(delta) |> maybe_merge_usage(usage)
        {:cont, %{acc | message: message}}

      %{"type" => "message_stop"}, acc ->
        {:halt, finalize(acc)}

      _other, acc ->
        {:cont, acc}
    end)
    |> case do
      {:error, _} = err -> err
      %{message: _} = acc -> finalize(acc)
      finalized -> finalized
    end
  end

  @doc "Count the tokens that a Messages request would use, without sending it."
  @spec count_tokens(keyword() | map()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def count_tokens(opts) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Client.build()
    |> Req.post(url: @count_path, json: payload)
    |> handle_response()
  end

  defp split(opts) when is_list(opts) do
    {client_opts, rest} = ReqAnthropic.split_client_opts(opts)
    {client_opts, Map.new(rest)}
  end

  defp split(opts) when is_map(opts) do
    opts |> Map.to_list() |> split()
  end

  defp chunks(%Req.Response.Async{} = async), do: async
  defp chunks(binary) when is_binary(binary), do: [binary]
  defp chunks(list) when is_list(list), do: list

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp handle_response({:ok, %Req.Response{} = resp}), do: {:error, Error.from_response(resp)}
  defp handle_response({:error, %Error{} = err}), do: {:error, err}
  defp handle_response({:error, exception}), do: {:error, exception}

  defp apply_delta(%{"type" => "text", "text" => text} = block, %{
         "type" => "text_delta",
         "text" => append
       }) do
    %{block | "text" => text <> append}
  end

  defp apply_delta(%{"type" => "tool_use", "input" => input} = block, %{
         "type" => "input_json_delta",
         "partial_json" => partial
       }) do
    Map.put(block, "input", partial_concat(input, partial))
  end

  defp apply_delta(%{"type" => "thinking", "thinking" => thinking} = block, %{
         "type" => "thinking_delta",
         "thinking" => append
       }) do
    %{block | "thinking" => thinking <> append}
  end

  defp apply_delta(block, _delta), do: block

  defp partial_concat(nil, partial), do: partial
  defp partial_concat(existing, partial) when is_binary(existing), do: existing <> partial
  defp partial_concat(_existing, partial), do: partial

  defp finalize(%{message: nil}),
    do: {:error, %Error{type: "incomplete_stream", message: "no message_start event received"}}

  defp finalize(%{message: message, blocks: blocks}) do
    content =
      blocks
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {_, block} -> block end)

    {:ok, Map.put(message, "content", content)}
  end

  defp maybe_merge_usage(message, nil), do: message

  defp maybe_merge_usage(%{"usage" => existing} = message, usage) when is_map(existing) do
    Map.put(message, "usage", Map.merge(existing, usage))
  end

  defp maybe_merge_usage(message, usage), do: Map.put(message, "usage", usage)
end
