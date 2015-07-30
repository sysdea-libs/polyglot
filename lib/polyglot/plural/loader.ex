defmodule Polyglot.Plural.Loader do
  require Record
  Record.defrecordp :xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecordp :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")

  def load_all_plurals(file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRules"
    for el <- q(qs, xml) do
      [xmlAttribute(value: locales)] = q("./@locales", el)
      rules = for el2 <- q("./pluralRule", el) do
        [xmlAttribute(value: count)] = q("./@count", el2)
        [xmlText(value: rule)] = q("./text()", el2)
        {List.to_string(count), extract_rule(rule)}
      end
      {locales, rules}
    end
  end

  def load_all_ranges(file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRanges"
    for el <- q(qs, xml) do
      [xmlAttribute(value: locales)] = q("./@locales", el)
      rules = for el2 <- q("./pluralRange", el) do
        [xmlAttribute(value: result)] = q("./@result", el2)
        [xmlAttribute(value: from)] = q("./@start", el2)
        [xmlAttribute(value: to)] = q("./@end", el2)
        {List.to_string(result), List.to_string(from), List.to_string(to)}
      end
      {locales, rules}
    end
  end

  defp xml_file(path) do
    {:ok, f} = :file.read_file(path)

    {xml, _} = f
               |> :binary.bin_to_list
               |> :xmerl_scan.string

    xml
  end

  defp q(s, xml) do
    :xmerl_xpath.string(to_char_list(s), xml)
  end

  defp extract_rule(rule) do
    Regex.run(~r/^[^@]*/, List.to_string(rule))
    |> List.first
    |> String.strip
  end

end