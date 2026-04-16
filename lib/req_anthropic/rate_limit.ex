defmodule ReqAnthropic.RateLimit do
  @moduledoc """
  Parsed rate-limit metadata from Anthropic API response headers.

  Every response from the Anthropic API includes rate-limit headers.
  This struct captures the ones most useful for client-side throttling:

    * `requests_remaining` — requests left in the current window
    * `tokens_remaining` — tokens left in the current window
    * `retry_after` — seconds to wait before retrying (present on 429s)

  ## Extracting from a response

  The plugin automatically parses these headers and stashes the struct
  in `Req.Response` private data. Use `ReqAnthropic.rate_limit/1` to
  retrieve it:

      {:ok, resp} = ReqAnthropic.Client.build(opts) |> Req.post(...)
      rate_limit = ReqAnthropic.rate_limit(resp)
      rate_limit.requests_remaining  #=> 42
  """

  defstruct [:requests_remaining, :tokens_remaining, :retry_after]

  @type t :: %__MODULE__{
          requests_remaining: non_neg_integer() | nil,
          tokens_remaining: non_neg_integer() | nil,
          retry_after: non_neg_integer() | nil
        }

  @doc """
  Build a `%RateLimit{}` from a `%Req.Response{}` by extracting and
  parsing the relevant headers.
  """
  @spec from_response(Req.Response.t()) :: t()
  def from_response(%Req.Response{headers: headers}) do
    %__MODULE__{
      requests_remaining:
        parse_int(header(headers, "anthropic-ratelimit-requests-remaining")),
      tokens_remaining:
        parse_int(header(headers, "anthropic-ratelimit-tokens-remaining")),
      retry_after:
        parse_int(header(headers, "retry-after"))
    }
  end

  defp header(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end
end
