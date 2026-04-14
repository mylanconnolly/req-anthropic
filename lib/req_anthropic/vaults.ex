defmodule ReqAnthropic.Vaults do
  @moduledoc """
  The Managed Agents Vaults API: store third-party credentials that
  sessions can use to authenticate with MCP servers at runtime. Credentials
  themselves are managed by `ReqAnthropic.Vaults.Credentials`.

      {:ok, vault} = ReqAnthropic.Vaults.create(display_name: "Alice")

      {:ok, _cred} =
        ReqAnthropic.Vaults.Credentials.create(vault["id"],
          display_name: "Alice's Slack",
          auth: %{
            type: "static_bearer",
            mcp_server_url: "https://mcp.slack.com/mcp",
            token: "xoxp-..."
          }
        )
  """

  alias ReqAnthropic.{Beta, Client, Error}

  @path "/v1/vaults"
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
    {query, opts} = Keyword.split(opts, [:limit, :page, :order, :include_archived])

    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.get(url: @path, params: query)
    |> handle()
  end

  @spec update(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def update(id, opts) when is_binary(id) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.patch(url: @path <> "/" <> id, json: payload)
    |> handle()
  end

  @doc "Archive a vault. Cascades to all credentials in the vault."
  @spec archive(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def archive(id, opts \\ []) when is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.post(url: @path <> "/" <> id <> "/archive")
    |> handle()
  end

  @doc "Hard-delete a vault. Use `archive/2` when you need an audit trail."
  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def delete(id, opts \\ []) when is_binary(id) do
    opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.delete(url: @path <> "/" <> id)
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
