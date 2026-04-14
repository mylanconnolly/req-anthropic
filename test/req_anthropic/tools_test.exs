defmodule ReqAnthropic.ToolsTest do
  use ExUnit.Case, async: true

  alias ReqAnthropic.Tools

  test "web_search builds the right type" do
    assert %{type: "web_search_20250305", name: "web_search"} = Tools.web_search()
    assert %{max_uses: 5} = Tools.web_search(max_uses: 5)
  end

  test "bash, text_editor, memory have stable types" do
    assert %{type: "bash_20250124"} = Tools.bash()

    assert %{type: "text_editor_20250728", name: "str_replace_based_edit_tool"} =
             Tools.text_editor()

    assert %{type: "memory_20250818"} = Tools.memory()
  end

  test "computer requires display dims and tags a beta" do
    tool = Tools.computer(display_width_px: 1024, display_height_px: 768)
    assert tool.type == "computer_20250124"
    assert tool.display_width_px == 1024
    assert tool.__beta__ == "computer-use-2025-01-24"
  end

  test "advisor tool tags its beta header" do
    assert %{__beta__: "advisor-tool-2026-03-01"} = Tools.advisor()
  end

  test "custom requires name, description, and input_schema" do
    tool =
      Tools.custom(
        name: "get_weather",
        description: "fetch weather",
        input_schema: %{type: "object", properties: %{city: %{type: "string"}}}
      )

    assert tool.name == "get_weather"
    assert tool.description == "fetch weather"
    assert tool.input_schema.type == "object"

    assert_raise KeyError, fn -> Tools.custom(name: "x") end
  end

  test "required_betas collects beta markers from a tool list" do
    tools = [
      Tools.advisor(),
      Tools.computer(display_width_px: 800, display_height_px: 600),
      Tools.web_search()
    ]

    betas = Tools.required_betas(tools)
    assert "advisor-tool-2026-03-01" in betas
    assert "computer-use-2025-01-24" in betas
    assert length(betas) == 2
  end

  test "strip removes internal markers" do
    tools = [Tools.advisor()]
    [stripped] = Tools.strip(tools)
    refute Map.has_key?(stripped, :__beta__)
  end
end
