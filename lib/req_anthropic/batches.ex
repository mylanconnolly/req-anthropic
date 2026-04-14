defmodule ReqAnthropic.Batches do
  @moduledoc """
  The Message Batches API: submit large volumes of Messages requests for
  asynchronous processing at a 50% discount.

      ReqAnthropic.Batches.create(
        requests: [
          %{
            custom_id: "req-1",
            params: %{
              model: "claude-haiku-4-5",
              max_tokens: 256,
              messages: [%{role: "user", content: "ping"}]
            }
          }
        ]
      )

  Use `results/2` to stream the JSONL results back as decoded maps.
  """

  alias ReqAnthropic.{Client, Error}

  @path "/v1/messages/batches"

  @spec create(keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def create(opts) do
    {client_opts, payload} = split(opts)

    client_opts
    |> Client.build()
    |> Req.post(url: @path, json: payload)
    |> handle()
  end

  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def get(id, opts \\ []) when is_binary(id) do
    opts
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id)
    |> handle()
  end

  @spec list(keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def list(opts \\ []) do
    {query, opts} = Keyword.split(opts, [:before_id, :after_id, :limit])

    opts
    |> Client.build()
    |> Req.get(url: @path, params: query)
    |> handle()
  end

  @spec cancel(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def cancel(id, opts \\ []) when is_binary(id) do
    opts
    |> Client.build()
    |> Req.post(url: @path <> "/" <> id <> "/cancel")
    |> handle()
  end

  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def delete(id, opts \\ []) when is_binary(id) do
    opts
    |> Client.build()
    |> Req.delete(url: @path <> "/" <> id)
    |> handle()
  end

  @doc """
  Stream the results of a completed batch. The results endpoint returns
  newline-delimited JSON; each yielded element is a decoded map.
  """
  @spec results(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def results(id, opts \\ []) when is_binary(id) do
    opts
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id <> "/results", into: :self)
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body |> chunks() |> jsonl_stream()}

      {:ok, %Req.Response{} = resp} ->
        {:error, Error.from_response(resp)}

      {:error, %Error{} = err} ->
        {:error, err}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp chunks(%Req.Response.Async{} = async), do: async
  defp chunks(binary) when is_binary(binary), do: [binary]
  defp chunks(list) when is_list(list), do: list

  defp jsonl_stream(chunks) do
    Stream.transform(
      chunks,
      fn -> "" end,
      &take_lines/2,
      &flush_lines/1,
      fn _ -> :ok end
    )
  end

  defp take_lines(data, buffer) do
    buffer = buffer <> data
    parts = String.split(buffer, "\n")
    {complete, [rest]} = Enum.split(parts, length(parts) - 1)
    {Enum.flat_map(complete, &decode_line/1), rest}
  end

  defp flush_lines(""), do: {[], :ok}
  defp flush_lines(line), do: {decode_line(line), :ok}

  defp decode_line(""), do: []

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, value} -> [value]
      {:error, _} -> []
    end
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
