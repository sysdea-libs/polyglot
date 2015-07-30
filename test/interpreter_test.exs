defmodule InterpreterTest do
  use ExUnit.Case

  def interpret(lang, str, args \\ %{}) do
    Polyglot.Interpreter.interpret(lang, str, args)
    |> :erlang.iolist_to_binary
    |> String.strip
  end

  test "interpreted simple strings" do
    assert interpret("en", "My simple string.")
           == "My simple string."
    assert interpret("en", "Hello {name}.", %{"name" => "Chris"})
           == "Hello Chris."
  end

  test "interpret plural" do
    str = """
    {num, plural,
      one {one item}
    other {# items}}
    """

    assert interpret("en", str, %{"num" => 5})
           == "5 items"
    assert interpret("en", str, %{"num" => "5"})
           == "5 items"
    assert interpret("en", str, %{"num" => 1})
           == "one item"
    assert interpret("en", str, %{"num" => "1"})
           == "one item"
    assert interpret("en", str, %{"num" => "1.0"})
           == "1.0 items"
    assert interpret("en", str, %{"num" => 1.5})
           == "1.5 items"
    assert interpret("en", str, %{"num" => "1.50"})
           == "1.50 items"
  end

  test "interpret select/plural" do
    en_str = """
    {gender, select,
        male {He}
      female {She}
       other {They}
    } found {{num_categories, plural,
                 one {one category}
               other {# categories}
             } in {num_results, plural,
                   one {one result}
                 other {# results}
               }}.
    """

    de_str = """
    {GENDER, select,
        male {Er}
      female {Sie}
       other {Sie}
    } fand {num_categories, plural,
                one {eine Kategorie}
              other {# Kategorien}
            } in {num_results, plural,
                  one {einem Ergebnis}
                other {# Ergebnisse}
              }.
    """

    assert interpret("en", en_str, %{"gender" => "female",
                                     "num_categories" => 2,
                                     "num_results" => 1})
           == "She found 2 categories in one result."

    assert interpret("en", en_str, %{"gender" => "male",
                                     "num_categories" => 1,
                                     "num_results" => 2})
           == "He found one category in 2 results."

    assert interpret("de", de_str, %{"gender" => "female",
                                     "num_categories" => 2,
                                     "num_results" => 1})
           == "Sie fand 2 Kategorien in einem Ergebnis."

    assert interpret("de", de_str, %{"gender" => "other",
                                     "num_categories" => 0,
                                     "num_results" => 5})
           == "Sie fand 0 Kategorien in 5 Ergebnisse."
  end

  test "function_from_string ordinal" do
    str = """
    You came in {place, ordinal,
                    one {#st}
                    two {#nd}
                    few {#rd}
                  other {#th}} place.
    """

    assert interpret("en", str, %{"place" => 1})
           == "You came in 1st place."
    assert interpret("en", str, %{"place" => 22})
           == "You came in 22nd place."
    assert interpret("en", str, %{"place" => 103})
           == "You came in 103rd place."
    assert interpret("en", str, %{"place" => 7})
           == "You came in 7th place."
  end

  test "function_from_string range" do
    str = """
    {range, range,
        one {# den}
        few {# dny}
       many {# dne}
      other {# dní}}.
    """

    assert interpret("cs", str, %{"range" => {0,1}})
           == "0-1 den."
    assert interpret("cs", str, %{"range" => {2,4}})
           == "2-4 dny."
    assert interpret("cs", str, %{"range" => {2,"3,50"}})
           == "2-3,50 dne."
    assert interpret("cs", str, %{"range" => {0,5}})
           == "0-5 dní."
  end
end
