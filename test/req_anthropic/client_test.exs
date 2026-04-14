defmodule ReqAnthropic.ClientTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.{Client, Error}

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    :ok
  end

  test "build returns a Req struct with ReqAnthropic options registered" do
    req = Client.build()

    assert %Req.Request{} = req
    assert :api_key in req.registered_options
    assert :anthropic_version in req.registered_options
    assert :beta in req.registered_options
  end

  test "auth step sets x-api-key, anthropic-version, and base_url" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["test-key"] = Plug.Conn.get_req_header(conn, "x-api-key")
      assert ["2023-06-01"] = Plug.Conn.get_req_header(conn, "anthropic-version")
      Req.Test.json(conn, %{ok: true})
    end)

    {:ok, %Req.Response{status: 200}} =
      Client.build()
      |> Req.get(url: "/v1/anything")
  end

  test "call-site api_key overrides app env" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["sk-override"] = Plug.Conn.get_req_header(conn, "x-api-key")
      Req.Test.json(conn, %{ok: true})
    end)

    {:ok, _} =
      [api_key: "sk-override"]
      |> Client.build()
      |> Req.get(url: "/v1/anything")
  end

  test "merges and dedupes anthropic-beta from call-site and app env" do
    Application.put_env(:req_anthropic, :beta, ["app-beta"])

    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["call-beta,app-beta"] = Plug.Conn.get_req_header(conn, "anthropic-beta")
      Req.Test.json(conn, %{ok: true})
    end)

    {:ok, _} =
      [beta: ["call-beta", "app-beta"]]
      |> Client.build()
      |> Req.get(url: "/v1/anything")
  after
    Application.delete_env(:req_anthropic, :beta)
  end

  test "non-2xx responses are normalized into ReqAnthropic.Error" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("request-id", "req_123")
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        400,
        Jason.encode!(%{
          "type" => "error",
          "error" => %{"type" => "invalid_request_error", "message" => "bad model"}
        })
      )
    end)

    assert {:error, %Error{} = err} =
             Client.build() |> Req.get(url: "/v1/anything")

    assert err.type == "invalid_request_error"
    assert err.message == "bad model"
    assert err.status == 400
    assert err.request_id == "req_123"
  end

  test "raises AuthError when no key is resolvable" do
    Application.delete_env(:req_anthropic, :api_key)
    Application.delete_env(:req_anthropic, :plug)

    assert_raise ReqAnthropic.AuthError, fn ->
      Client.build() |> Req.get(url: "/v1/anything")
    end
  after
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
  end
end
