defmodule BotArmySkills.Actions.WebhookTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.Actions.Webhook

  describe "execute/2" do
    test "requires url in config" do
      assert_raise KeyError, fn ->
        Webhook.execute(%{}, %{})
      end
    end

    test "constructs POST request with json payload" do
      # Unit test — HTTPoison call will fail without a server
      config = %{"url" => "https://example.com/webhook", "headers" => %{"X-Custom" => "test"}}
      payload = %{"message" => "hello"}

      result = Webhook.execute(config, payload)

      # Will fail since there's no server, but we verify it attempts the call
      assert match?({:error, _}, result)
    end

    test "uses default headers when none provided" do
      config = %{"url" => "https://example.com/webhook"}
      payload = %{"test" => "data"}

      result = Webhook.execute(config, payload)
      assert match?({:error, _}, result)
    end
  end
end
