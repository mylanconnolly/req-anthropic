defmodule ReqAnthropic.Agents do
  @moduledoc """
  The Managed Agents Agents API: define reusable, versioned agent
  configurations (model, system prompt, tools, MCP servers, skills).

  All endpoints are gated behind the `managed-agents-2026-04-01` beta
  header, which is added automatically.

      {:ok, agent} =
        ReqAnthropic.Agents.create(
          model: "claude-sonnet-4-6",
          name: "My first agent",
          system: "You are helpful."
        )
  """

  alias ReqAnthropic.{Beta, Client, Error}

  @path "/v1/agents"
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

  @doc """
  Update an agent. Updating an agent creates a new version; prior versions
  remain accessible.
  """
  @spec update(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def update(id, opts) when is_binary(id) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Beta.ensure(@beta)
    |> Client.build()
    |> Req.patch(url: @path <> "/" <> id, json: payload)
    |> handle()
  end

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
