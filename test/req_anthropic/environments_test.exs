defmodule ReqAnthropic.EnvironmentsTest do
  use ExUnit.Case, async: false

  alias ReqAnthropic.Environments

  setup do
    Application.put_env(:req_anthropic, :api_key, "test-key")
    Application.put_env(:req_anthropic, :plug, {Req.Test, ReqAnthropic})
    :ok
  end

  test "full CRUD hits /v1/environments with the managed-agents beta" do
    Req.Test.stub(ReqAnthropic, fn conn ->
      assert ["managed-agents-2026-04-01"] = Plug.Conn.get_req_header(conn, "anthropic-beta")

      case {conn.method, conn.request_path} do
        {"POST", "/v1/environments"} ->
          assert conn.body_params["name"] == "python-env"
          assert conn.body_params["config"]["packages"]["pip"] == ["pandas"]
          Req.Test.json(conn, %{"id" => "env_1"})

        {"GET", "/v1/environments/env_1"} ->
          Req.Test.json(conn, %{"id" => "env_1"})

        {"GET", "/v1/environments"} ->
          Req.Test.json(conn, %{"data" => []})

        {"PATCH", "/v1/environments/env_1"} ->
          Req.Test.json(conn, %{"id" => "env_1", "name" => "renamed"})

        {"DELETE", "/v1/environments/env_1"} ->
          Req.Test.json(conn, %{"id" => "env_1", "deleted" => true})
      end
    end)

    assert {:ok, %{"id" => "env_1"}} =
             Environments.create(
               name: "python-env",
               config: %{type: "cloud", packages: %{pip: ["pandas"]}}
             )

    assert {:ok, %{"id" => "env_1"}} = Environments.get("env_1")
    assert {:ok, %{"data" => []}} = Environments.list()
    assert {:ok, %{"name" => "renamed"}} = Environments.update("env_1", name: "renamed")
    assert {:ok, %{"deleted" => true}} = Environments.delete("env_1")
  end
end
