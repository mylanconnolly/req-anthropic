defmodule ReqAnthropic.VaultsTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Vaults
  alias ReqAnthropic.Vaults.Credentials

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "vaults CRUD + archive" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["managed-agents-2026-04-01"] = Plug.Conn.get_req_header(conn, "anthropic-beta")

      case {conn.method, conn.request_path} do
        {"POST", "/v1/vaults"} ->
          assert conn.body_params["display_name"] == "Alice"
          Req.Test.json(conn, %{"id" => "vlt_1", "display_name" => "Alice"})

        {"GET", "/v1/vaults/vlt_1"} ->
          Req.Test.json(conn, %{"id" => "vlt_1"})

        {"GET", "/v1/vaults"} ->
          Req.Test.json(conn, %{"data" => []})

        {"PATCH", "/v1/vaults/vlt_1"} ->
          Req.Test.json(conn, %{"id" => "vlt_1", "display_name" => "Renamed"})

        {"POST", "/v1/vaults/vlt_1/archive"} ->
          Req.Test.json(conn, %{"id" => "vlt_1", "archived_at" => "2026-04-14T00:00:00Z"})

        {"DELETE", "/v1/vaults/vlt_1"} ->
          Req.Test.json(conn, %{"id" => "vlt_1", "deleted" => true})
      end
    end)

    assert {:ok, %{"id" => "vlt_1"}} = Vaults.create(display_name: "Alice")
    assert {:ok, %{"id" => "vlt_1"}} = Vaults.get("vlt_1")
    assert {:ok, %{"data" => []}} = Vaults.list()
    assert {:ok, %{"display_name" => "Renamed"}} = Vaults.update("vlt_1", display_name: "Renamed")
    assert {:ok, %{"archived_at" => _}} = Vaults.archive("vlt_1")
    assert {:ok, %{"deleted" => true}} = Vaults.delete("vlt_1")
  end

  test "credentials CRUD + archive under a vault" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["managed-agents-2026-04-01"] = Plug.Conn.get_req_header(conn, "anthropic-beta")

      case {conn.method, conn.request_path} do
        {"POST", "/v1/vaults/vlt_1/credentials"} ->
          assert conn.body_params["auth"]["type"] == "static_bearer"
          Req.Test.json(conn, %{"id" => "crd_1"})

        {"GET", "/v1/vaults/vlt_1/credentials/crd_1"} ->
          Req.Test.json(conn, %{"id" => "crd_1"})

        {"GET", "/v1/vaults/vlt_1/credentials"} ->
          Req.Test.json(conn, %{"data" => [%{"id" => "crd_1"}]})

        {"PATCH", "/v1/vaults/vlt_1/credentials/crd_1"} ->
          Req.Test.json(conn, %{"id" => "crd_1", "updated" => true})

        {"POST", "/v1/vaults/vlt_1/credentials/crd_1/archive"} ->
          Req.Test.json(conn, %{"id" => "crd_1", "archived_at" => "2026-04-14T00:00:00Z"})

        {"DELETE", "/v1/vaults/vlt_1/credentials/crd_1"} ->
          Req.Test.json(conn, %{"id" => "crd_1", "deleted" => true})
      end
    end)

    assert {:ok, %{"id" => "crd_1"}} =
             Credentials.create("vlt_1",
               display_name: "Slack",
               auth: %{
                 type: "static_bearer",
                 mcp_server_url: "https://mcp.slack.com/mcp",
                 token: "xoxp-..."
               }
             )

    assert {:ok, %{"id" => "crd_1"}} = Credentials.get("vlt_1", "crd_1")
    assert {:ok, %{"data" => [_]}} = Credentials.list("vlt_1")

    assert {:ok, %{"updated" => true}} =
             Credentials.update("vlt_1", "crd_1", auth: %{type: "static_bearer", token: "new"})

    assert {:ok, %{"archived_at" => _}} = Credentials.archive("vlt_1", "crd_1")
    assert {:ok, %{"deleted" => true}} = Credentials.delete("vlt_1", "crd_1")
  end
end
