defmodule MessageFormatTest.C do
  use MessageFormat

  compile_string :t!, "en", "simple", "My simple string."

  compile_string :t!, "en", "plural", """
  {NUM, plural,
    one {one item}
  other {# items}
  }
  """

  compile_string :t!, "en", "select+plural", """
  {GENDER, select,
      male {He}
    female {She}
     other {They}
  } found {NUM_CATEGORIES, plural,
              one {one category}
            other {# categories}
          } in {NUM_RESULTS, plural,
                one {one result}
              other {# results}
            }.
  """

  compile_string :t!, "de", "select+plural", """
  {GENDER, select,
      male {Er}
    female {Sie}
     other {Sie}
  } fand {NUM_CATEGORIES, plural,
              one {eine Kategorie}
            other {# Kategorien}
          } in {NUM_RESULTS, plural,
                one {einem Ergebnis}
              other {# Ergebnisse}
            }.
  """

  compile_string :t!, "en", "ordinal", """
  You came in {PLACE, ordinal,
                  one {#st}
                  two {#nd}
                  few {#rd}
                other {#th}} place.
  """

  compile_string :t!, "cs", "range", """
  {RANGE, range,
      one {# den}
      few {# dny}
     many {# dne}
    other {# dní}}.
  """
end

defmodule MessageFormatTest do
  use ExUnit.Case

  test "compile_string simple strings, no args" do
    assert MessageFormatTest.C.t!("en", "simple") == "My simple string."
  end

  test "compile_string plural" do
    assert MessageFormatTest.C.t!("en", "plural", %{num: 5})
           == "5 items"
    assert MessageFormatTest.C.t!("en", "plural", %{num: "5"})
           == "5 items"
    assert MessageFormatTest.C.t!("en", "plural", %{num: 1})
           == "one item"
    assert MessageFormatTest.C.t!("en", "plural", %{num: "1"})
           == "one item"
    assert MessageFormatTest.C.t!("en", "plural", %{num: "1.0"})
           == "1.0 items"
    assert MessageFormatTest.C.t!("en", "plural", %{num: 1.5})
           == "1.5 items"
    assert MessageFormatTest.C.t!("en", "plural", %{num: "1.50"})
           == "1.50 items"
  end

  test "compile_string select/plural functions" do
    assert MessageFormatTest.C.t!("en", "select+plural",
                                 %{gender: "female", num_categories: 2, num_results: 1})
           == "She found 2 categories in one result."

    assert MessageFormatTest.C.t!("en", "select+plural",
                                 %{gender: "male", num_categories: 1, num_results: 2})
           == "He found one category in 2 results."

    assert MessageFormatTest.C.t!("de", "select+plural",
                                 %{gender: "female", num_categories: 2, num_results: 1})
           == "Sie fand 2 Kategorien in einem Ergebnis."

    assert MessageFormatTest.C.t!("de", "select+plural",
                                 %{gender: "other", num_categories: 0, num_results: 5})
           == "Sie fand 0 Kategorien in 5 Ergebnisse."
  end

  test "compile_string ordinal" do
    assert MessageFormatTest.C.t!("en", "ordinal", %{place: 1})
           == "You came in 1st place."
    assert MessageFormatTest.C.t!("en", "ordinal", %{place: 22})
           == "You came in 22nd place."
    assert MessageFormatTest.C.t!("en", "ordinal", %{place: 103})
           == "You came in 103rd place."
    assert MessageFormatTest.C.t!("en", "ordinal", %{place: 7})
           == "You came in 7th place."
  end

  test "compile_string range" do
    assert MessageFormatTest.C.t!("cs", "range", %{range: {0,1}})
           == "0-1 den."
    assert MessageFormatTest.C.t!("cs", "range", %{range: {2,4}})
           == "2-4 dny."
    assert MessageFormatTest.C.t!("cs", "range", %{range: {2,"3,50"}})
           == "2-3,50 dne."
    assert MessageFormatTest.C.t!("cs", "range", %{range: {0,5}})
           == "0-5 dní."
  end
end
