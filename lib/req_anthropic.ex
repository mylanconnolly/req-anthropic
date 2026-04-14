defmodule ReqAnthropic do
  @moduledoc """
  An Anthropic-focused API client built on Req.

  Two layers are shipped together:

    * The plugin layer — `attach/2` registers Anthropic-aware options on a
      `%Req.Request{}`, sets auth headers, normalizes errors, and resolves
      relative URLs against the API base URL. Power users can drop this on
      any Req struct and call the API directly.

    * The resource layer — modules like `ReqAnthropic.Messages`,
      `ReqAnthropic.Models`, `ReqAnthropic.Files`, and
      `ReqAnthropic.Batches` build a Req via `attach/2` and expose a small,
      Anthropic-shaped API.

  ## Authentication

  An API key is resolved at request time in this order:

    1. The `:api_key` option passed to the call.
    2. `Application.get_env(:req_anthropic, :api_key)`.
    3. `System.get_env("ANTHROPIC_API_KEY")`.

  If no key can be resolved, `ReqAnthropic.AuthError` is raised before the
  request is sent.

  ## Examples

      ReqAnthropic.Messages.create(
        model: "claude-haiku-4-5",
        max_tokens: 256,
        messages: [%{role: "user", content: "ping"}]
      )

      Req.new()
      |> ReqAnthropic.attach(api_key: "sk-...")
      |> Req.post!(url: "/v1/messages", json: %{...})
  """

  alias ReqAnthropic.{Beta, Error}

  @default_base_url "https://api.anthropic.com"
  @default_version "2023-06-01"

  @options [
    :api_key,
    :base_url,
    :anthropic_version,
    :beta,
    :decode_errors
  ]

  @doc """
  Attach the ReqAnthropic plugin to a `%Req.Request{}`.

  Registers the ReqAnthropic-specific options and appends request/response
  steps to set auth headers, resolve the base URL, and normalize errors.

  ## Options

    * `:api_key` - the Anthropic API key. Falls back to the application
      environment and then `ANTHROPIC_API_KEY`.
    * `:base_url` - defaults to `"https://api.anthropic.com"`.
    * `:anthropic_version` - the `anthropic-version` header value, defaults
      to `"2023-06-01"`.
    * `:beta` - a string or list of strings to send as `anthropic-beta`.
    * `:decode_errors` - when `true` (default), non-2xx responses are
      converted into `{:error, %ReqAnthropic.Error{}}`.
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, options \\ []) do
    request
    |> Req.Request.register_options(@options)
    |> Req.Request.merge_options(options)
    |> Req.Request.append_request_steps(req_anthropic_auth: &auth_step/1)
    |> Req.Request.append_response_steps(req_anthropic_decode_error: &decode_error_step/1)
  end

  @doc """
  Send a request through a freshly-built ReqAnthropic client.

  Equivalent to `ReqAnthropic.Client.build(opts) |> Req.request()`.
  """
  @spec request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request(opts) do
    {client_opts, req_opts} = split_client_opts(opts)
    client_opts |> ReqAnthropic.Client.build() |> Req.request(req_opts)
  end

  @doc false
  def split_client_opts(opts) do
    Keyword.split(opts, @options ++ [:req_options])
  end

  @doc false
  def default_base_url, do: @default_base_url

  @doc false
  def default_version, do: @default_version

  defp auth_step(%Req.Request{} = request) do
    api_key = resolve_api_key(request)
    version = resolve(request, :anthropic_version, @default_version)

    betas =
      Beta.merge([
        request.options[:beta],
        Application.get_env(:req_anthropic, :beta)
      ])

    request =
      request
      |> Req.Request.put_header("anthropic-version", version)
      |> maybe_put_header("x-api-key", api_key)
      |> maybe_put_header("anthropic-beta", Beta.header_value(betas))

    case request.options[:base_url] || Application.get_env(:req_anthropic, :base_url) do
      nil -> Req.merge(request, base_url: @default_base_url)
      base_url -> Req.merge(request, base_url: base_url)
    end
  end

  defp resolve_api_key(request) do
    cond do
      key = request.options[:api_key] -> key
      key = Application.get_env(:req_anthropic, :api_key) -> key
      key = System.get_env("ANTHROPIC_API_KEY") -> key
      Map.has_key?(request.options, :plug) -> "test-key"
      true -> raise ReqAnthropic.AuthError
    end
  end

  defp resolve(request, key, default) do
    request.options[key] || Application.get_env(:req_anthropic, key, default)
  end

  defp maybe_put_header(request, _name, nil), do: request
  defp maybe_put_header(request, name, value), do: Req.Request.put_header(request, name, value)

  defp decode_error_step({request, response}) do
    decode? = Map.get(request.options, :decode_errors, true)

    cond do
      not decode? -> {request, response}
      response.status in 200..299 -> {request, response}
      true -> {request, Error.from_response(response)}
    end
  end
end
