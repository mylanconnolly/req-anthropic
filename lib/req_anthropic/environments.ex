defmodule ReqAnthropic.Environments do
  @moduledoc """
  The Managed Agents Environments API: configure container templates
  (packages, network policy) that sessions run inside.

      {:ok, env} =
        ReqAnthropic.Environments.create(
          name: "python-data-analysis",
          config: %{
            type: "cloud",
            packages: %{pip: ["pandas", "numpy"]},
            networking: %{type: "limited", allow_package_managers: true}
          }
        )
  """

  alias ReqAnthropic.{Beta, Client, Error}

  @path "/v1/environments"
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
  Update an environment. Fields omitted from the payload preserve their
  existing values (per the Anthropic API's documented semantics).
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
