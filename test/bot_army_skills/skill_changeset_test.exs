defmodule BotArmySkills.SkillChangesetTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.Skill

  describe "Skill changeset" do
    test "valid with required fields" do
      attrs = %{
        tenant_id: "00000000-0000-0000-0000-000000000001",
        name: "Summarize",
        slug: "summarize",
        markdown_content: "---\nname: summarize\n---\nContent here",
        version: 1
      }

      changeset = Skill.changeset(%Skill{}, attrs)
      assert changeset.valid?
    end

    test "validates slug format" do
      attrs = %{
        tenant_id: "00000000-0000-0000-0000-000000000001",
        name: "Bad Slug",
        slug: "Bad-Slug!",
        markdown_content: "content",
        version: 1
      }

      changeset = Skill.changeset(%Skill{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :slug)
    end

    test "accepts valid slug" do
      attrs = %{
        tenant_id: "00000000-0000-0000-0000-000000000001",
        name: "Summarize",
        slug: "summarize_text",
        markdown_content: "content",
        version: 1
      }

      changeset = Skill.changeset(%Skill{}, attrs)
      assert changeset.valid?
    end

    test "requires tenant_id, name, slug, markdown_content" do
      changeset = Skill.changeset(%Skill{}, %{})
      refute changeset.valid?

      error_fields = Keyword.keys(changeset.errors)

      # version has a default of 1, so it won't be in errors
      for field <- [:tenant_id, :name, :slug, :markdown_content] do
        assert field in error_fields, "Expected #{field} in errors"
      end
    end
  end
end
