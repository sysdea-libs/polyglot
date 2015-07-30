defmodule Polyglot.Plural.Loader do
  require Record
  Record.defrecordp :xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecordp :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")

  def load_plural_rules(lang, file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRules[contains(concat(' ', @locales, ' '), ' #{lang} ')]/pluralRule"
    for el <- q(qs, xml) do
      [xmlAttribute(value: count)] = q("./@count", el)
      [xmlText(value: rule)] = q("./text()", el)
      {List.to_string(count), extract_rule(rule)}
    end
  end

  def load_range_rules(lang, file) do
    xml = xml_file(:code.priv_dir(:polyglot) ++ file)
    qs = "//pluralRanges[contains(concat(' ', @locales, ' '), ' #{lang} ')]/pluralRange"
    for el <- q(qs, xml) do
      [xmlAttribute(value: result)] = q("./@result", el)
      [xmlAttribute(value: from)] = q("./@start", el)
      [xmlAttribute(value: to)] = q("./@end", el)
      {List.to_string(result), List.to_string(from), List.to_string(to)}
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