defmodule ReqAnthropic.Error do
  @moduledoc """
  Normalized error returned by ReqAnthropic when the Anthropic API responds
  with a non-2xx status, or when the client itself fails before sending.
  """

  defexception [:type, :message, :status, :request_id, :raw]

  @type t :: %__MODULE__{
          type: String.t() | nil,
          message: String.t() | nil,
          status: pos_integer() | nil,
          request_id: String.t() | nil,
          raw: term()
        }

  @impl true
  def message(%__MODULE__{type: type, message: msg, status: status}) do
    parts = [type && "(#{type})", msg, status && "[HTTP #{status}]"]
    parts |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  @doc """
  Build an Error from a Req response. The Anthropic API returns errors as
  `%{"type" => "error", "error" => %{"type" => ..., "message" => ...}}`.
  """
  @spec from_response(Req.Response.t()) :: t()
  def from_response(%Req.Response{status: status, body: body, headers: headers}) do
    {type, message} =
      case body do
        %{"error" => %{"type" => t, "message" => m}} -> {t, m}
        %{"type" => t, "message" => m} -> {t, m}
        _ -> {nil, nil}
      end

    %__MODULE__{
      type: type,
      message: message,
      status: status,
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

defmodule ReqAnthropic.AuthError do
  @moduledoc """
  Raised when no API key can be resolved. ReqAnthropic checks, in order:

    1. The `:api_key` option passed to the function.
    2. `Application.get_env(:req_anthropic, :api_key)`.
    3. The `ANTHROPIC_API_KEY` environment variable.
  """

  defexception message: """
               No Anthropic API key found. Set one of:

                 * the :api_key option on the call
                 * config :req_anthropic, api_key: "..."
                 * the ANTHROPIC_API_KEY environment variable
               """
end
