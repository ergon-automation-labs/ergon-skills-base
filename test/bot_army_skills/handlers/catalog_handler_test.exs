defmodule BotArmySkills.Handlers.CatalogHandlerTest do
  use ExUnit.Case, async: true

  alias BotArmySkills.Handlers.CatalogHandler

  @moduletag :handlers

  test "canonical list includes playwright_operator" do
    assert %{"skills" => skills} = CatalogHandler.handle_canonical_list(%{})
    slugs = Enum.map(skills, & &1["slug"])
    assert "playwright_operator" in slugs
  end
end
