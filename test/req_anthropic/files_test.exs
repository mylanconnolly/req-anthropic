defmodule ReqAnthropic.FilesTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Files

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "create uploads multipart and adds the files-api beta header" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/files"
      assert ["files-api-2025-04-14"] = Plug.Conn.get_req_header(conn, "anthropic-beta")

      ["multipart/form-data" <> _] = Plug.Conn.get_req_header(conn, "content-type")
      assert %{"file" => %Plug.Upload{}} = conn.body_params

      Req.Test.json(conn, %{"id" => "file_1", "filename" => "hi.txt"})
    end)

    tmp =
      Path.join(System.tmp_dir!(), "req_anthropic_test_#{System.unique_integer([:positive])}.txt")

    File.write!(tmp, "hello")

    try do
      assert {:ok, %{"id" => "file_1"}} = Files.create(path: tmp)
    after
      File.rm(tmp)
    end
  end

  test "list/get/delete hit the right URLs" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["files-api-2025-04-14"] = Plug.Conn.get_req_header(conn, "anthropic-beta")

      case {conn.method, conn.request_path} do
        {"GET", "/v1/files"} ->
          Req.Test.json(conn, %{"data" => []})

        {"GET", "/v1/files/file_1"} ->
          Req.Test.json(conn, %{"id" => "file_1"})

        {"DELETE", "/v1/files/file_1"} ->
          Req.Test.json(conn, %{"id" => "file_1", "deleted" => true})
      end
    end)

    assert {:ok, %{"data" => []}} = Files.list()
    assert {:ok, %{"id" => "file_1"}} = Files.get("file_1")
    assert {:ok, %{"deleted" => true}} = Files.delete("file_1")
  end

  test "content returns raw bytes" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.request_path == "/v1/files/file_1/content"

      conn
      |> Plug.Conn.put_resp_content_type("application/octet-stream")
      |> Plug.Conn.send_resp(200, <<1, 2, 3>>)
    end)

    assert {:ok, <<1, 2, 3>>} = Files.content("file_1")
  end
end
