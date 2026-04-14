defmodule ReqAnthropic.Files do
  @moduledoc """
  The Files API: upload files for use across multiple requests.

  This is a beta endpoint and the `files-api-2025-04-14` beta header is
  added automatically.

      {:ok, file} = ReqAnthropic.Files.create(path: "report.pdf")
      ReqAnthropic.Files.list()
      ReqAnthropic.Files.delete(file["id"])
  """

  alias ReqAnthropic.{Client, Error}

  @path "/v1/files"
  @beta "files-api-2025-04-14"

  @doc """
  Upload a file. Pass either `:path` (a path on disk) or `:content` (an
  iodata body) plus `:filename`. `:content_type` is optional but recommended.
  """
  @spec create(keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def create(opts) do
    {file_field, opts} = pop_file_field(opts)
    opts = ensure_beta(opts)

    opts
    |> Client.build()
    |> Req.post(url: @path, form_multipart: [file: file_field])
    |> handle()
  end

  @spec list(keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def list(opts \\ []) do
    {query, opts} = Keyword.split(opts, [:before_id, :after_id, :limit])
    opts = ensure_beta(opts)

    opts
    |> Client.build()
    |> Req.get(url: @path, params: query)
    |> handle()
  end

  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def get(id, opts \\ []) when is_binary(id) do
    opts
    |> ensure_beta()
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id)
    |> handle()
  end

  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t() | Exception.t()}
  def delete(id, opts \\ []) when is_binary(id) do
    opts
    |> ensure_beta()
    |> Client.build()
    |> Req.delete(url: @path <> "/" <> id)
    |> handle()
  end

  @doc "Download the raw bytes of a file."
  @spec content(String.t(), keyword()) :: {:ok, binary()} | {:error, Error.t() | Exception.t()}
  def content(id, opts \\ []) when is_binary(id) do
    opts
    |> ensure_beta()
    |> Client.build()
    |> Req.get(url: @path <> "/" <> id <> "/content")
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{} = resp} -> {:error, Error.from_response(resp)}
      {:error, %Error{} = err} -> {:error, err}
      {:error, exception} -> {:error, exception}
    end
  end

  defp pop_file_field(opts) do
    case Keyword.pop(opts, :path) do
      {nil, opts} ->
        {content, opts} = Keyword.pop(opts, :content)
        {filename, opts} = Keyword.pop(opts, :filename, "upload.bin")
        {content_type, opts} = Keyword.pop(opts, :content_type, "application/octet-stream")
        {{filename, content, content_type: content_type}, opts}

      {path, opts} ->
        filename = Keyword.get(opts, :filename, Path.basename(path))
        content_type = Keyword.get(opts, :content_type, MIME.from_path(path))
        opts = Keyword.drop(opts, [:filename, :content_type])
        {{File.read!(path), filename: filename, content_type: content_type}, opts}
    end
  end

  defp ensure_beta(opts), do: ReqAnthropic.Beta.ensure(opts, @beta)

  defp handle({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp handle({:ok, %Req.Response{} = resp}), do: {:error, Error.from_response(resp)}
  defp handle({:error, %Error{} = err}), do: {:error, err}
  defp handle({:error, exception}), do: {:error, exception}
end
