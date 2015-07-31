defmodule PolyglotTest.C do
  use Polyglot

  locale_string "en", "simple", "My simple string."

  locale_string "en", "interpolate", "Hello {NAME}."

  locale_string "en", "plural", """
  {num, plural,
    one {one item}
  other {# items}}
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

  test "function_from_string simple strings" do
    assert PolyglotTest.C.t!("en", "simple") == "My simple string."
    assert PolyglotTest.C.t!("en", "interpolate", %{"name" => "Chris"})
           == "Hello Chris."
  end

  test "function_from_string plural" do
    assert PolyglotTest.C.t!("en", "plural", %{"num" => 5})
           == "5 items"
    assert PolyglotTest.C.t!("en", "plural", %{"num" => "5"})
           == "5 items"
    assert PolyglotTest.C.t!("en", "plural", %{"num" => 1})
           == "one item"
    assert PolyglotTest.C.t!("en", "plural", %{"num" => "1"})
           == "one item"
    assert PolyglotTest.C.t!("en", "plural", %{"num" => "1.0"})
           == "1.0 items"
    assert PolyglotTest.C.t!("en", "plural", %{"num" => 1.5})
           == "1.5 items"
    assert PolyglotTest.C.t!("en", "plural", %{"num" => "1.50"})
           == "1.50 items"
  end

  test "function_from_string select/plural functions" do
    assert PolyglotTest.C.t!("en", "select+plural",
                             %{"gender" => "female", "num_categories" => 2, "num_results" => 1})
           == "She found 2 categories in one result."

    assert PolyglotTest.C.t!("en", "select+plural",
                             %{"gender" => "male", "num_categories" => 1, "num_results" => 2})
           == "He found one category in 2 results."

    assert PolyglotTest.C.t!("de", "select+plural",
                             %{"gender" => "female", "num_categories" => 2, "num_results" => 1})
           == "Sie fand 2 Kategorien in einem Ergebnis."

    assert PolyglotTest.C.t!("de", "select+plural",
                             %{"gender" => "other", "num_categories" => 0, "num_results" => 5})
           == "Sie fand 0 Kategorien in 5 Ergebnisse."
  end

  test "function_from_string ordinal" do
    assert PolyglotTest.C.t!("en", "ordinal", %{"place" => 1})
           == "You came in 1st place."
    assert PolyglotTest.C.t!("en", "ordinal", %{"place" => 22})
           == "You came in 22nd place."
    assert PolyglotTest.C.t!("en", "ordinal", %{"place" => 103})
           == "You came in 103rd place."
    assert PolyglotTest.C.t!("en", "ordinal", %{"place" => 7})
           == "You came in 7th place."
  end

  test "function_from_string range" do
    assert PolyglotTest.C.t!("cs", "range", %{"range" => {0,1}})
           == "0-1 den."
    assert PolyglotTest.C.t!("cs", "range", %{"range" => {2,4}})
           == "2-4 dny."
    assert PolyglotTest.C.t!("cs", "range", %{"range" => {2,"3,50"}})
           == "2-3,50 dne."
    assert PolyglotTest.C.t!("cs", "range", %{"range" => {0,5}})
           == "0-5 dní."
  end

  test "function_from_file" do
    assert PolyglotTest.C.t!("en", "test message")
           == "Hello from the translator."
    assert PolyglotTest.C.t!("en", "test message 2", %{"num" => 3})
           == "3 items"
  end
end
