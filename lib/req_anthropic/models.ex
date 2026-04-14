defmodule ReqAnthropic.Models do
  @moduledoc """
  The Models API: list available Claude models, retrieve a specific model,
  and look up per-model capabilities.

  Results are cached in an ETS table owned by the application supervisor.
  Pass `cache: false` to bypass the cache. Configure the TTL with
  `config :req_anthropic, models_cache_ttl: :timer.hours(2)`.
  """

  alias ReqAnthropic.{Client, Error, Model}

  @table ReqAnthropic.Models.Cache
  @list_path "/v1/models"
  @default_ttl :timer.hours(1)

  @doc """
  List all models available to your API key. Paginates the API
  transparently and returns a list of `%ReqAnthropic.Model{}`.
  """
  @spec list(keyword()) :: {:ok, [Model.t()]} | {:error, Error.t() | Exception.t()}
  def list(opts \\ []) do
    {use_cache?, opts} = Keyword.pop(opts, :cache, true)

    case use_cache? && cache_get(:list) do
      {:ok, models} ->
        {:ok, models}

      _ ->
        case fetch_all(opts) do
          {:ok, models} ->
            cache_put(:list, models)
            Enum.each(models, fn %Model{id: id} = m -> cache_put({:model, id}, m) end)
            {:ok, models}

          error ->
            error
        end
    end
  end

  @doc "Same as `list/1` but raises on error."
  @spec list!(keyword()) :: [Model.t()]
  def list!(opts \\ []) do
    case list(opts) do
      {:ok, models} -> models
      {:error, error} -> raise error
    end
  end

  @doc """
  Retrieve a single model by id.
  """
  @spec get(String.t(), keyword()) :: {:ok, Model.t()} | {:error, Error.t() | Exception.t()}
  def get(id, opts \\ []) when is_binary(id) do
    {use_cache?, opts} = Keyword.pop(opts, :cache, true)

    case use_cache? && cache_get({:model, id}) do
      {:ok, model} ->
        {:ok, model}

      _ ->
        opts
        |> Client.build()
        |> Req.get(url: @list_path <> "/" <> id)
        |> case do
          {:ok, %Req.Response{status: 200, body: body}} ->
            model = Model.from_map(body)
            cache_put({:model, id}, model)
            {:ok, model}

          {:ok, %Req.Response{} = resp} ->
            {:error, Error.from_response(resp)}

          {:error, %Error{} = err} ->
            {:error, err}

          {:error, exception} ->
            {:error, exception}
        end
    end
  end

  @doc "Same as `get/2` but raises on error."
  @spec get!(String.t(), keyword()) :: Model.t()
  def get!(id, opts \\ []) do
    case get(id, opts) do
      {:ok, model} -> model
      {:error, error} -> raise error
    end
  end

  @doc """
  Return the static capabilities table for a model id (or `%Model{}` struct).
  """
  @spec capabilities(String.t() | Model.t()) :: Model.Capabilities.t()
  def capabilities(%Model{id: id}), do: Model.Capabilities.for_id(id)
  def capabilities(id) when is_binary(id), do: Model.Capabilities.for_id(id)

  @doc "Drop everything from the cache."
  @spec clear_cache() :: :ok
  def clear_cache do
    :ets.delete_all_objects(@table)
    :ok
  end

  defp fetch_all(opts, acc \\ [], after_id \\ nil) do
    query =
      [limit: 1000]
      |> then(fn q -> if after_id, do: Keyword.put(q, :after_id, after_id), else: q end)

    opts
    |> Client.build()
    |> Req.get(url: @list_path, params: query)
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"data" => data} = body}} ->
        models = data |> Enum.map(&Model.from_map/1) |> Enum.reverse() |> Kernel.++(acc)

        cond do
          Map.get(body, "has_more") == true and Map.get(body, "last_id") ->
            fetch_all(opts, models, Map.get(body, "last_id"))

          true ->
            {:ok, Enum.reverse(models)}
        end

      {:ok, %Req.Response{} = resp} ->
        {:error, Error.from_response(resp)}

      {:error, %Error{} = err} ->
        {:error, err}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp cache_get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(key, value) do
    ttl = Application.get_env(:req_anthropic, :models_cache_ttl, @default_ttl)
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table, {key, value, expires_at})
    :ok
  rescue
    ArgumentError -> :ok
  end
end
