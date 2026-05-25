defmodule BotArmySkills.Handlers.BionicReadingHandlerTest do
  use ExUnit.Case, async: true

  alias BotArmySkills.Handlers.BionicReadingHandler

  @moduletag :handlers

  describe "handle_transform/1" do
    test "transforms simple text with markdown bold" do
      result = BionicReadingHandler.handle_transform(%{"text" => "hello world"})

      assert result["ok"] == true
      assert result["text"] == "**he**llo **wo**rld"
      assert result["stats"]["words"] == 2
      assert result["stats"]["bolded"] == 2
    end

    test "skips 1-char words, bolds 2-char words" do
      result = BionicReadingHandler.handle_transform(%{"text" => "I am ok"})

      assert result["ok"] == true
      assert result["text"] == "I **a**m **o**k"
      assert result["stats"]["bolded"] == 2
    end

    test "preserves punctuation" do
      result = BionicReadingHandler.handle_transform(%{"text" => "Hello, world!"})

      assert result["ok"] == true
      assert result["text"] == "**He**llo, **wo**rld!"
    end

    test "supports html format" do
      result =
        BionicReadingHandler.handle_transform(%{"text" => "hello world", "format" => "html"})

      assert result["ok"] == true
      assert result["text"] == "<b>he</b>llo <b>wo</b>rld"
    end

    test "respects custom ratio" do
      result = BionicReadingHandler.handle_transform(%{"text" => "elephant", "ratio" => 0.5})

      assert result["ok"] == true
      assert result["text"] == "**elep**hant"
    end

    test "ratio as string percentage" do
      result = BionicReadingHandler.handle_transform(%{"text" => "elephant", "ratio" => "50"})

      assert result["ok"] == true
      assert result["text"] == "**elep**hant"
    end

    test "empty text returns empty" do
      result = BionicReadingHandler.handle_transform(%{"text" => ""})

      assert result["ok"] == true
      assert result["text"] == ""
      assert result["stats"]["words"] == 0
    end

    test "missing text key returns empty" do
      result = BionicReadingHandler.handle_transform(%{})

      assert result["ok"] == true
      assert result["text"] == ""
    end

    test "invalid ratio defaults to 0.3" do
      result = BionicReadingHandler.handle_transform(%{"text" => "hello", "ratio" => "invalid"})

      assert result["ok"] == true
      assert result["text"] == "**he**llo"
    end

    test "stats include ratio used" do
      result = BionicReadingHandler.handle_transform(%{"text" => "hello", "ratio" => 0.4})

      assert result["stats"]["ratio"] == 0.4
    end

    test "preserves multiple spaces and formatting" do
      result = BionicReadingHandler.handle_transform(%{"text" => "hello  world"})

      assert result["ok"] == true
      assert result["text"] == "**he**llo  **wo**rld"
    end
  end
end
