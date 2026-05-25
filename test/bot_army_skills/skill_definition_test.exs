defmodule BotArmySkills.SkillDefinitionTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.SkillDefinition

  describe "from_db_row/1" do
    test "parses a map row with frontmatter" do
      row = %{
        "id" => "skill-id-123",
        "tenant_id" => "tenant-id-456",
        "name" => "summarize",
        "slug" => "summarize",
        "markdown_content" =>
          "---\nname: summarize\nslug: summarize\ntriggers: bot.army.command.summarize\nllm_hint: fast\n---\nSummarize this: {{ payload.content }}",
        "version" => 1,
        "is_active" => true
      }

      defn = SkillDefinition.from_db_row(row)

      assert defn.name == :summarize
      assert defn.slug == "summarize"
      assert defn.tenant_id == "tenant-id-456"
      assert defn.version == 1
      assert defn.is_active == true
      assert defn.db_id == "skill-id-123"
      assert defn.llm_hint == :fast
      assert defn.triggers == ["bot.army.command.summarize"]
      assert defn.markdown_content =~ "Summarize this:"
    end

    test "handles markdown without frontmatter" do
      row = %{
        "id" => "skill-id",
        "tenant_id" => "tenant-id",
        "name" => "plain_skill",
        "slug" => "plain_skill",
        "markdown_content" => "Just a plain template with no frontmatter",
        "version" => 1,
        "is_active" => true
      }

      defn = SkillDefinition.from_db_row(row)

      assert defn.name == :plain_skill
      assert defn.slug == "plain_skill"
      assert defn.llm_hint == :none
      assert defn.triggers == []
      assert defn.markdown_content == "Just a plain template with no frontmatter"
    end

    test "handles atom keys in row map" do
      row = %{
        id: "skill-id",
        tenant_id: "tenant-id",
        name: "extract",
        slug: "extract",
        markdown_content:
          "---\nname: extract\ntriggers: bot.army.command.extract\n---\nExtract: {{ payload.content }}",
        version: 2,
        is_active: true
      }

      defn = SkillDefinition.from_db_row(row)

      assert defn.name == :extract
      assert defn.slug == "extract"
      assert defn.version == 2
    end

    test "defaults llm_hint to :none when not in frontmatter" do
      row = %{
        "id" => "id",
        "tenant_id" => "tid",
        "name" => "simple",
        "slug" => "simple",
        "markdown_content" => "---\nname: simple\n---\nDo something",
        "version" => 1,
        "is_active" => true
      }

      defn = SkillDefinition.from_db_row(row)
      assert defn.llm_hint == :none
    end
  end

  describe "struct fields" do
    test "creates struct with required fields" do
      defn = %SkillDefinition{
        name: :test,
        slug: "test",
        tenant_id: "tid",
        markdown_content: "Test content",
        version: 1
      }

      assert defn.name == :test
      assert defn.slug == "test"
      assert defn.llm_hint == nil
      assert defn.triggers == nil
      assert defn.is_active == nil
      assert defn.description == nil
      assert defn.db_id == nil
    end
  end
end
