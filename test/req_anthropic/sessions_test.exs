defmodule ReqAnthropic.SessionsTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Sessions

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "create posts agent + environment_id" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.request_path == "/v1/sessions"
      assert ["managed-agents-2026-04-01"] = Plug.Conn.get_req_header(conn, "anthropic-beta")
      assert conn.body_params["agent"] == "agent_1"
      assert conn.body_params["environment_id"] == "env_1"
      Req.Test.json(conn, %{"id" => "sess_1", "status" => "idle"})
    end)

    assert {:ok, %{"id" => "sess_1"}} =
             Sessions.create(agent: "agent_1", environment_id: "env_1")
  end

  test "get/list/archive/delete/events hit the right URLs" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v1/sessions/sess_1"} ->
          Req.Test.json(conn, %{"id" => "sess_1"})

        {"GET", "/v1/sessions"} ->
          assert %{"agent_id" => "agent_1"} = conn.query_params
          Req.Test.json(conn, %{"data" => [%{"id" => "sess_1"}]})

        {"POST", "/v1/sessions/sess_1/archive"} ->
          Req.Test.json(conn, %{"id" => "sess_1", "archived_at" => "2026-04-14T00:00:00Z"})

        {"DELETE", "/v1/sessions/sess_1"} ->
          Req.Test.json(conn, %{"id" => "sess_1", "deleted" => true})

        {"GET", "/v1/sessions/sess_1/events"} ->
          assert %{"limit" => "50"} = conn.query_params
          Req.Test.json(conn, %{"data" => []})
      end
    end)

    assert {:ok, %{"id" => "sess_1"}} = Sessions.get("sess_1")
    assert {:ok, %{"data" => _}} = Sessions.list(agent_id: "agent_1")
    assert {:ok, %{"archived_at" => _}} = Sessions.archive("sess_1")
    assert {:ok, %{"deleted" => true}} = Sessions.delete("sess_1")
    assert {:ok, %{"data" => []}} = Sessions.events("sess_1", limit: 50)
  end

  test "send_events, send_message, interrupt POST to /events" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/sessions/sess_1/events"
      events = conn.body_params["events"]
      assert is_list(events)
      send(self(), {:events, events})
      Req.Test.json(conn, %{"accepted" => length(events)})
    end)

    assert {:ok, %{"accepted" => 1}} =
             Sessions.send_events("sess_1", [
               %{type: "user.message", content: [%{type: "text", text: "hi"}]}
             ])

    assert {:ok, %{"accepted" => 1}} = Sessions.send_message("sess_1", "hello")

    assert {:ok, %{"accepted" => 2}} = Sessions.interrupt("sess_1", message: "change direction")
  end

  test "stream parses SSE events from /stream" do
    sse = """
    event: agent.message
    data: {"type":"agent.message","id":"evt_1","content":[{"type":"text","text":"hi"}]}

    event: session.status
    data: {"type":"session.status","status":"idle"}

    """

    Req.Test.stub(ReqAnthropic, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/sessions/sess_1/stream"

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, sse)
    end)

    assert {:ok, stream} = Sessions.stream("sess_1")
    events = Enum.to_list(stream)
    assert [%{"type" => "agent.message"}, %{"type" => "session.status"}] = events
  end
end
