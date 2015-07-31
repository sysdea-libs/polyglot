defmodule PolyglotTest.C do
  use Polyglot

  locale_string "en", "simple", "My simple string."

  locale_string "en", "interpolate", "Hello {NAME}."

  locale_string "en", "plural", """
  {num, plural,
    one {one item}
  other {# items}}
  """

  locale_string "en", "select fallthrough", """
  {taxableArea, select,
            yes {An additional tax will be collected.}
          other {No taxes apply.}}
  """

  locale_string "en", "select+plural", """
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

  locale_string "de", "select+plural", """
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

  locale_string "en", "ordinal", """
  You came in {place, selectordinal,
                  one {#st}
                  two {#nd}
                  few {#rd}
                other {#th}} place.
  """

  locale_string "cs", "range", """
  {range, range,
      one {# den}
      few {# dny}
     many {# dne}
    other {# dní}}.
  """

  locale "en", Path.join(__DIR__, "/fixtures/en.lang")
end

defmodule PolyglotTest do
  use ExUnit.Case

  defp run(lang, key, args \\ %{}) do
    PolyglotTest.C.t!(lang, key, args)
    |> :erlang.iolist_to_binary
    |> String.strip
  end

  test "function_from_string simple strings" do
    assert PolyglotTest.C.t!("en", "simple") == ["My simple string."]
    assert PolyglotTest.C.t!("en", "interpolate", %{"name" => "Chris"})
           == ["Hello ", "Chris", "."]
  end

  test "function_from_string plural" do
    assert run("en", "plural", %{"num" => 5})
           == "5 items"
    assert run("en", "plural", %{"num" => "5"})
           == "5 items"
    assert run("en", "plural", %{"num" => 1})
           == "one item"
    assert run("en", "plural", %{"num" => "1"})
           == "one item"
    assert run("en", "plural", %{"num" => "1.0"})
           == "1.0 items"
    assert run("en", "plural", %{"num" => 1.5})
           == "1.5 items"
    assert run("en", "plural", %{"num" => "1.50"})
           == "1.50 items"
  end

  test "function_from_string fallthrough select" do
    assert run("en", "select fallthrough", %{"taxablearea" => "yes"})
           == "An additional tax will be collected."
    assert run("en", "select fallthrough", %{"taxablearea" => "no"})
           == "No taxes apply."
  end

  test "function_from_string select/plural functions" do
    assert run("en", "select+plural",
                             %{"gender" => "female", "num_categories" => 2, "num_results" => 1})
           == "She found 2 categories in one result."

    assert run("en", "select+plural",
                             %{"gender" => "male", "num_categories" => 1, "num_results" => 2})
           == "He found one category in 2 results."

    assert run("de", "select+plural",
                             %{"gender" => "female", "num_categories" => 2, "num_results" => 1})
           == "Sie fand 2 Kategorien in einem Ergebnis."

    assert run("de", "select+plural",
                             %{"gender" => "other", "num_categories" => 0, "num_results" => 5})
           == "Sie fand 0 Kategorien in 5 Ergebnisse."
  end

  test "function_from_string ordinal" do
    assert run("en", "ordinal", %{"place" => 1})
           == "You came in 1st place."
    assert run("en", "ordinal", %{"place" => 22})
           == "You came in 22nd place."
    assert run("en", "ordinal", %{"place" => 103})
           == "You came in 103rd place."
    assert run("en", "ordinal", %{"place" => 7})
           == "You came in 7th place."
  end

  test "function_from_string range" do
    assert run("cs", "range", %{"range" => {0,1}})
           == "0-1 den."
    assert run("cs", "range", %{"range" => {2,4}})
           == "2-4 dny."
    assert run("cs", "range", %{"range" => {2,"3,50"}})
           == "2-3,50 dne."
    assert run("cs", "range", %{"range" => {0,5}})
           == "0-5 dní."
  end

  test "function_from_file" do
    assert run("en", "test message")
           == "Hello from the translator."
    assert run("en", "test message 2", %{"num" => 3})
           == "3 items"
  end
end
