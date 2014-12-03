defmodule MessageFormatTest.Compiled do
  use MessageFormat

  compile_string :t!, "en", "simple", "My simple string."

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
end

defmodule MessageFormatTest do
  use ExUnit.Case

  test "compile_string simple strings, no args" do
    assert MessageFormatTest.Compiled.t!("en", "simple") == "My simple string."
  end

  test "compile_string select/plural functions" do
    assert MessageFormatTest.Compiled.t!("en", "select+plural",
                                         %{gender: "female", num_categories: 2, num_results: 1})
           == "She found 2 categories in one result."

    assert MessageFormatTest.Compiled.t!("en", "select+plural",
                                         %{gender: "male", num_categories: 1, num_results: 2})
           == "He found one category in 2 results."

    assert MessageFormatTest.Compiled.t!("de", "select+plural",
                                         %{gender: "female", num_categories: 2, num_results: 1})
           == "Sie fand 2 Kategorien in einem Ergebnis."

    assert MessageFormatTest.Compiled.t!("de", "select+plural",
                                         %{gender: "other", num_categories: 0, num_results: 5})
           == "Sie fand 0 Kategorien in 5 Ergebnisse."
  end
end
