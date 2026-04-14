defmodule ReqAnthropic.ConversationTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Conversation

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "appends turns and forwards the full history on each send" do
    turn_counter = :counters.new(1, [])

    Req.Test.stub(ReqAnthropic, fn conn ->
      :counters.add(turn_counter, 1, 1)
      turn = :counters.get(turn_counter, 1)

      assert conn.request_path == "/v1/messages"
      assert conn.body_params["model"] == "claude-haiku-4-5"
      assert conn.body_params["system"] == "be brief"

      messages = conn.body_params["messages"]
      assert length(messages) == turn * 2 - 1

      reply =
        case turn do
          1 -> "Elixir is a functional language."
          2 -> "OTP is its concurrency framework."
        end

      Req.Test.json(conn, %{
        "id" => "msg_#{turn}",
        "role" => "assistant",
        "content" => [%{"type" => "text", "text" => reply}]
      })
    end)

    convo =
      Conversation.new(
        model: "claude-haiku-4-5",
        max_tokens: 32,
        system: "be brief"
      )
      |> Conversation.user("Tell me about Elixir.")

    assert {:ok, convo} = Conversation.send(convo)
    assert Conversation.last_text(convo) == "Elixir is a functional language."
    assert length(convo.messages) == 2

    convo = Conversation.user(convo, "What about OTP?")
    assert {:ok, convo} = Conversation.send(convo)
    assert Conversation.last_text(convo) == "OTP is its concurrency framework."
    assert length(convo.messages) == 4
  end

  test "new/1 raises if :model is missing" do
    assert_raise ArgumentError, fn -> Conversation.new(max_tokens: 10) end
  end

  test "propagates errors from Messages.create" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        500,
        Jason.encode!(%{
          "type" => "error",
          "error" => %{"type" => "api_error", "message" => "boom"}
        })
      )
    end)

    convo =
      Conversation.new(model: "claude-haiku-4-5", max_tokens: 16)
      |> Conversation.user("hi")

    assert {:error, %ReqAnthropic.Error{type: "api_error"}} = Conversation.send(convo)
  end
end
