defmodule ReqAnthropic.RateLimited do
  @moduledoc """
  Returned when the Anthropic API responds with HTTP 429 (Too Many Requests).

  The `retry_after` field (seconds) is promoted to the top level for
  ergonomic pattern matching:

      case ReqAnthropic.Messages.create(opts) do
        {:ok, body} -> body
        {:error, %ReqAnthropic.RateLimited{retry_after: n}} -> Process.sleep(n * 1000)
        {:error, other} -> raise other
      end

  The full `%ReqAnthropic.RateLimit{}` struct is available in the
  `rate_limit` field for detailed quota information.
  """

  alias ReqAnthropic.RateLimit

  defexception [:retry_after, :rate_limit, :message, :request_id, :raw]

  @type t :: %__MODULE__{
          retry_after: non_neg_integer() | nil,
          rate_limit: RateLimit.t(),
          message: String.t() | nil,
          request_id: String.t() | nil,
          raw: term()
        }

  @impl true
  def message(%__MODULE__{message: msg, retry_after: retry_after}) do
    parts = ["(rate_limited)", msg, retry_after && "retry after #{retry_after}s"]
    parts |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  @doc """
  Build a `%RateLimited{}` from a `%Req.Response{}` and a pre-parsed
  `%RateLimit{}`.
  """
  @spec from_response(Req.Response.t(), RateLimit.t()) :: t()
  def from_response(%Req.Response{body: body, headers: headers}, %RateLimit{} = rate_limit) do
    msg =
      case body do
        %{"error" => %{"message" => m}} -> m
        %{"message" => m} -> m
        _ -> nil
      end

    %__MODULE__{
      retry_after: rate_limit.retry_after,
      rate_limit: rate_limit,
      message: msg,
      request_id: header(headers, "request-id"),
      raw: body
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
end
