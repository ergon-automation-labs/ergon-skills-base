defmodule BotArmySkills.TenantActionChangesetTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.TenantAction

  describe "TenantAction changeset" do
    test "valid with required fields" do
      attrs = %{
        tenant_id: "00000000-0000-0000-0000-000000000001",
        slug: "notify_team",
        type: "slack",
        config_json: %{"webhook_url" => "https://hooks.slack.com/test"}
      }

      changeset = TenantAction.changeset(%TenantAction{}, attrs)
      assert changeset.valid?
    end

    test "validates type inclusion" do
      attrs = %{
        tenant_id: "00000000-0000-0000-0000-000000000001",
        slug: "bad_action",
        type: "carrier_pigeon",
        config_json: %{}
      }

      changeset = TenantAction.changeset(%TenantAction{}, attrs)
      refute changeset.valid?
    end

    test "accepts all valid action types" do
      for type <- BotArmySkills.TenantAction.action_types() do
        attrs = %{
          tenant_id: "00000000-0000-0000-0000-000000000001",
          slug: "action_#{type}",
          type: type,
          config_json: %{}
        }

        changeset = TenantAction.changeset(%TenantAction{}, attrs)
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "validates slug format" do
      attrs = %{
        tenant_id: "00000000-0000-0000-0000-000000000001",
        slug: "Invalid-Slug",
        type: "webhook",
        config_json: %{}
      }

      changeset = TenantAction.changeset(%TenantAction{}, attrs)
      refute changeset.valid?
    end
  end

  describe "action_types/0" do
    test "returns all supported action types" do
      types = TenantAction.action_types()
      assert types == ~w(webhook nats_publish nats_request api_call slack email)
    end
  end
end
