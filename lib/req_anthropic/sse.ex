defmodule ReqAnthropic.SSE do
  @moduledoc """
  Minimal Server-Sent Events parser used by streaming endpoints.

  The Anthropic streaming protocol emits events of the form:

      event: <name>
      data: <json>

  separated by blank lines. `parse_stream/1` takes any enumerable of binary
  chunks (most commonly a `Req.Response.Async`) and returns a `Stream` that
  yields parsed event maps. The `:type` key is taken from the JSON `data`
  payload (Anthropic always includes it). Cross-chunk event boundaries are
  handled by buffering between elements.

  Lines of any other shape (`id:`, `retry:`, `:` comments) are ignored.
  Multi-line `data:` payloads are concatenated with `\\n` per the SSE spec.
  """

  @doc """
  Parse a stream of binary chunks into a stream of decoded SSE events.

  Each yielded element is a map decoded from the event's `data:` field, or
  `{:error, %ReqAnthropic.Error{}}` if a `data:` payload fails to decode.
  Events without a `data:` line (e.g. bare `event: ping` keep-alives) are
  yielded as `%{"type" => name}` so callers can still see them.
  """
  @spec parse_stream(Enumerable.t()) :: Enumerable.t()
  def parse_stream(chunks) do
    chunks
    |> Stream.transform(
      fn -> "" end,
      &chunk/2,
      &flush/1,
      fn _ -> :ok end
    )
  end

  defp chunk(data, buffer) do
    buffer = buffer <> data
    {events, rest} = take_events(buffer, [])
    {events, rest}
  end

  defp flush("") do
    {[], :ok}
  end

  defp flush(buffer) do
    case parse_event(buffer) do
      :skip -> {[], :ok}
      event -> {[event], :ok}
    end
  end

  defp take_events(buffer, acc) do
    case split_event(buffer) do
      {raw, rest} ->
        case parse_event(raw) do
          :skip -> take_events(rest, acc)
          event -> take_events(rest, [event | acc])
        end

      :more ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp split_event(buffer) do
    case :binary.match(buffer, ["\n\n", "\r\n\r\n"]) do
      {pos, len} ->
        <<raw::binary-size(pos), _::binary-size(len), rest::binary>> = buffer
        {raw, rest}

      :nomatch ->
        :more
    end
  end

  defp parse_event(raw) do
    raw
    |> String.split(["\r\n", "\n"])
    |> Enum.reduce(%{event: nil, data: []}, &accumulate_field/2)
    |> finalize()
  end

  defp accumulate_field(":" <> _comment, acc), do: acc

  defp accumulate_field(line, acc) do
    case String.split(line, ":", parts: 2) do
      ["event", value] -> %{acc | event: String.trim_leading(value)}
      ["data", value] -> %{acc | data: [String.trim_leading(value) | acc.data]}
      ["id", _value] -> acc
      ["retry", _value] -> acc
      [""] -> acc
      _ -> acc
    end
  end

  defp finalize(%{event: nil, data: []}), do: :skip

  defp finalize(%{event: event, data: []}) when is_binary(event) do
    %{"type" => event}
  end

  defp finalize(%{event: event, data: data}) do
    payload = data |> Enum.reverse() |> Enum.join("\n")

    case Jason.decode(payload) do
      {:ok, %{} = decoded} ->
        case event do
          nil -> decoded
          name -> Map.put_new(decoded, "type", name)
        end

      {:ok, other} ->
        %{"type" => event, "data" => other}

      {:error, error} ->
        {:error,
         %ReqAnthropic.Error{
           type: "stream_decode_error",
           message: Exception.message(error),
           raw: payload
         }}
    end
  end
end
