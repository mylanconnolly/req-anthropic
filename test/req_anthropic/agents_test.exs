defmodule ReqAnthropic.AgentsTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Agents

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "create posts to /v1/agents with managed-agents beta header" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/agents"
      assert ["managed-agents-2026-04-01"] = Plug.Conn.get_req_header(conn, "anthropic-beta")
      assert conn.body_params["model"] == "claude-sonnet-4-6"
      assert conn.body_params["name"] == "Test"

      Req.Test.json(conn, %{"id" => "agent_1", "version" => 1})
    end)

    assert {:ok, %{"id" => "agent_1"}} = Agents.create(model: "claude-sonnet-4-6", name: "Test")
  end

  test "get, list, update, delete hit the right URLs" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["managed-agents-2026-04-01"] = Plug.Conn.get_req_header(conn, "anthropic-beta")

      case {conn.method, conn.request_path} do
        {"GET", "/v1/agents/agent_1"} ->
          Req.Test.json(conn, %{"id" => "agent_1"})

        {"GET", "/v1/agents"} ->
          Req.Test.json(conn, %{"data" => [%{"id" => "agent_1"}]})

        {"PATCH", "/v1/agents/agent_1"} ->
          assert conn.body_params["system"] == "new prompt"
          Req.Test.json(conn, %{"id" => "agent_1", "version" => 2})

        {"DELETE", "/v1/agents/agent_1"} ->
          Req.Test.json(conn, %{"id" => "agent_1", "deleted" => true})
      end
    end)

    assert {:ok, %{"id" => "agent_1"}} = Agents.get("agent_1")
    assert {:ok, %{"data" => [_]}} = Agents.list()
    assert {:ok, %{"version" => 2}} = Agents.update("agent_1", system: "new prompt")
    assert {:ok, %{"deleted" => true}} = Agents.delete("agent_1")
  end

  test "merges managed-agents beta with caller-supplied beta" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      [header] = Plug.Conn.get_req_header(conn, "anthropic-beta")
      betas = String.split(header, ",")
      assert "managed-agents-2026-04-01" in betas
      assert "prompt-caching-2024-07-31" in betas

      Req.Test.json(conn, %{"id" => "agent_1"})
    end)

    assert {:ok, _} =
             Agents.create(
               model: "claude-sonnet-4-6",
               name: "Test",
               beta: "prompt-caching-2024-07-31"
             )
  end
end
