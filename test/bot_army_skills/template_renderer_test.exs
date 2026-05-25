defmodule BotArmySkills.TemplateRendererTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.TemplateRenderer

  describe "render/2 with payload variables" do
    test "replaces {{payload.key}} with value from payload" do
      template = "Hello {{ payload.name }}, your task is: {{ payload.task }}"

      vars = %{
        payload: %{"name" => "Abby", "task" => "review PRs"},
        context: %{},
        soul: %{},
        tenant_id: "test-tenant"
      }

      assert TemplateRenderer.render(template, vars) == "Hello Abby, your task is: review PRs"
    end

    test "resolves nested payload paths" do
      template = "User: {{ payload.user.name }}, Email: {{ payload.user.email }}"

      vars = %{
        payload: %{"user" => %{"name" => "Abby", "email" => "abby@test.com"}},
        context: %{},
        soul: %{},
        tenant_id: "test-tenant"
      }

      assert TemplateRenderer.render(template, vars) == "User: Abby, Email: abby@test.com"
    end

    test "renders empty string for missing payload keys" do
      template = "Name: {{ payload.name }}, Missing: {{ payload.missing }}"
      vars = %{payload: %{"name" => "Abby"}, context: %{}, soul: %{}, tenant_id: "test-tenant"}

      assert TemplateRenderer.render(template, vars) == "Name: Abby, Missing: "
    end

    test "renders non-string payload values with inspect" do
      template = "Count: {{ payload.count }}"
      vars = %{payload: %{"count" => 42}, context: %{}, soul: %{}, tenant_id: "test-tenant"}

      assert TemplateRenderer.render(template, vars) == "Count: 42"
    end
  end

  describe "render/2 with context variables" do
    test "replaces {{context.key}} with value from context" do
      template = "Energy: {{ context.energy_level }}, Focus: {{ context.focus_area }}"

      vars = %{
        payload: %{},
        context: %{"energy_level" => "high", "focus_area" => "deep work"},
        soul: %{},
        tenant_id: "test-tenant"
      }

      assert TemplateRenderer.render(template, vars) == "Energy: high, Focus: deep work"
    end

    test "renders empty string for missing context keys" do
      template = "Mode: {{ context.mode }}"
      vars = %{payload: %{}, context: %{}, soul: %{}, tenant_id: "test-tenant"}

      assert TemplateRenderer.render(template, vars) == "Mode: "
    end
  end

  describe "render/2 with soul variables" do
    test "replaces {{soul.key}} with value from soul config" do
      template = "I am {{ soul.identity.name }}. My role: {{ soul.identity.role }}"

      vars = %{
        payload: %{},
        context: %{},
        soul: %{"identity" => %{"name" => "Morgan", "role" => "Surface the next right action"}},
        tenant_id: "test-tenant"
      }

      assert TemplateRenderer.render(template, vars) ==
               "I am Morgan. My role: Surface the next right action"
    end

    test "renders empty string for missing soul keys" do
      template = "Name: {{ soul.identity.name }}"
      vars = %{payload: %{}, context: %{}, soul: %{}, tenant_id: "test-tenant"}

      assert TemplateRenderer.render(template, vars) == "Name: "
    end
  end

  describe "render/2 with action variables" do
    test "renders not-found for unknown action slug" do
      template = "Notifying via {{ action:nonexistent_action }}"
      vars = %{payload: %{}, context: %{}, soul: %{}, tenant_id: "test-tenant"}

      result = TemplateRenderer.render(template, vars)
      # DB not connected in unit tests, so action lookup fails gracefully
      assert result =~ "nonexistent_action"
    end

    test "action resolution fails gracefully without DB" do
      result =
        TemplateRenderer.render("Notifying via {{ action:notify_team }}", %{
          payload: %{},
          context: %{},
          soul: %{},
          tenant_id: "test-tenant"
        })

      # Since get_action hits DB and DB is not connected in unit tests,
      # it falls back to not-found
      assert result =~ "notify_team"
    end
  end

  describe "render/2 with mixed variable types" do
    test "handles template with all four variable types" do
      template = """
      Bot: {{ soul.identity.name }}
      Task: {{ payload.task }}
      Energy: {{ context.energy }}
      Action: {{ action:notify_team }}
      """

      vars = %{
        payload: %{"task" => "deploy"},
        context: %{"energy" => "high"},
        soul: %{"identity" => %{"name" => "Morgan"}},
        tenant_id: "test-tenant"
      }

      result = TemplateRenderer.render(template, vars)
      assert result =~ "Bot: Morgan"
      assert result =~ "Task: deploy"
      assert result =~ "Energy: high"
      assert result =~ "notify_team"
    end
  end

  describe "render/2 edge cases" do
    test "returns template unchanged when no variables present" do
      template = "No variables here"
      vars = %{payload: %{}, context: %{}, soul: %{}, tenant_id: "test-tenant"}

      assert TemplateRenderer.render(template, vars) == "No variables here"
    end

    test "handles empty template" do
      vars = %{payload: %{}, context: %{}, soul: %{}, tenant_id: "test-tenant"}
      assert TemplateRenderer.render("", vars) == ""
    end

    test "handles missing payload key in vars" do
      template = "Hello {{ payload.name }}"
      vars = %{context: %{}, soul: %{}, tenant_id: "test-tenant"}

      # No payload key — template variables left unreplaced
      result = TemplateRenderer.render(template, vars)
      assert result == "Hello {{ payload.name }}"
    end

    test "handles deeply nested paths" do
      template = "Value: {{ payload.a.b.c.d }}"

      vars = %{
        payload: %{"a" => %{"b" => %{"c" => %{"d" => "deep"}}}},
        context: %{},
        soul: %{},
        tenant_id: "test-tenant"
      }

      assert TemplateRenderer.render(template, vars) == "Value: deep"
    end
  end
end
