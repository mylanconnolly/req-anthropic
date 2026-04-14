defmodule ReqAnthropic.Vaults.Credentials do
  @moduledoc """
  Credentials nested under a vault. Each credential binds to a single
  `mcp_server_url` and provides auth material (static bearer token or
  OAuth refresh config) that the session runtime injects when the agent
  connects to the MCP server.

  Secret fields (`token`, `access_token`, `refresh_token`,
  `client_secret`) are write-only and never returned in responses.
  """

  alias ReqAnthropic.{Beta, Client, Error}

  @base "/v1/vaults"
  @beta "managed-agents-2026-04-01"

  defp path(vault_id), do: @base <> "/" <> vault_id <> "/credentials"
  defp path(vault_id, id), do: path(vault_id) <> "/" <> id

  @spec create(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def create(vault_id, opts) when is_binary(vault_id) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.post(url: path(vault_id), json: payload)
    |> handle()
  end

  @spec get(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def get(vault_id, id, opts \\ []) when is_binary(vault_id) and is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: path(vault_id, id))
    |> handle()
  end

  @spec list(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def list(vault_id, opts \\ []) when is_binary(vault_id) do
    {query, opts} = Keyword.split(opts, [:limit, :page, :order, :include_archived])

    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: path(vault_id), params: query)
    |> handle()
  end

  @spec update(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def update(vault_id, id, opts) when is_binary(vault_id) and is_binary(id) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.patch(url: path(vault_id, id), json: payload)
    |> handle()
  end

  @doc """
  Archive a credential. Purges the secret payload while preserving the
  record for auditing. Frees up the `mcp_server_url` for a replacement.
  """
  @spec archive(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def archive(vault_id, id, opts \\ []) when is_binary(vault_id) and is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.post(url: path(vault_id, id) <> "/archive")
    |> handle()
  end

  @spec delete(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | Exception.t()}
  def delete(vault_id, id, opts \\ []) when is_binary(vault_id) and is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.delete(url: path(vault_id, id))
    |> handle()
  end

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
