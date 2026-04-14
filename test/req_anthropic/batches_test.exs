defmodule ReqAnthropic.BatchesTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Batches

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "create POSTs to /v1/messages/batches" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/messages/batches"
      assert is_list(conn.body_params["requests"])
      Req.Test.json(conn, %{"id" => "batch_1", "processing_status" => "in_progress"})
    end)

    assert {:ok, %{"id" => "batch_1"}} =
             Batches.create(
               requests: [
                 %{
                   custom_id: "r1",
                   params: %{
                     model: "claude-haiku-4-5",
                     max_tokens: 16,
                     messages: [%{role: "user", content: "hi"}]
                   }
                 }
               ]
             )
  end

  test "get/list/cancel/delete hit the right URLs" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v1/messages/batches/batch_1"} ->
          Req.Test.json(conn, %{"id" => "batch_1"})

        {"GET", "/v1/messages/batches"} ->
          Req.Test.json(conn, %{"data" => [%{"id" => "batch_1"}]})

        {"POST", "/v1/messages/batches/batch_1/cancel"} ->
          Req.Test.json(conn, %{"id" => "batch_1", "processing_status" => "canceling"})

        {"DELETE", "/v1/messages/batches/batch_1"} ->
          Req.Test.json(conn, %{"id" => "batch_1", "deleted" => true})
      end
    end)

    assert {:ok, %{"id" => "batch_1"}} = Batches.get("batch_1")
    assert {:ok, %{"data" => _}} = Batches.list()
    assert {:ok, %{"processing_status" => "canceling"}} = Batches.cancel("batch_1")
    assert {:ok, %{"deleted" => true}} = Batches.delete("batch_1")
  end

  test "results streams JSONL as decoded maps" do
    body =
      [
        ~s({"custom_id":"r1","result":{"type":"succeeded"}}),
        ~s({"custom_id":"r2","result":{"type":"errored"}})
      ]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.request_path == "/v1/messages/batches/batch_1/results"

      conn
      |> Plug.Conn.put_resp_content_type("application/x-jsonl")
      |> Plug.Conn.send_resp(200, body)
    end)

    assert {:ok, stream} = Batches.results("batch_1")
    rows = Enum.to_list(stream)
    assert length(rows) == 2
    assert Enum.map(rows, & &1["custom_id"]) == ["r1", "r2"]
  end
end
