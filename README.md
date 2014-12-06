# Polyglot

An implementation of a MessageFormat-like string interpolator (PluralFormat + SelectFormat) in Elixir, for the purposes of translation when plural and gender forms are needed, especially when used together inside sentences ("She found 3 categories in one result"). Features ordinal/range extensions in addition to cardinal plurality and selection.

Polyglot is useful even if your needs are currently monolingual, for instance consider correctly producing the string "You are the 22nd visitor". A pleasant side-effect of solving that formatting can be making your application at least partly translation ready in the future.

## Stability

Polyglot is still in the early stages of development. Although the general syntax is fixed, the API is still open to change.

# Message Syntax

## Normal Interpolation

Provides no formatting other than ensuring that the parameter is printed as a string.

```
Hello #{NAME}.

# %{name: "Chris"} => "Hello Chris."
```

## SelectFormat

SelectFormat is the simplest formatter included, and simply selects from several outputs from a given input. For translation this most commonly is useful for gender selection.

```
{GENDER, select,
    male {He is}
  female {She is}
   other {They are}} great!

# %{gender: "male"}  => "He is great!"
# %{gender: "other"} => "They are great!"
```

## PluralFormat

PluralFormat is for cardinal pluralisation, such as "3 items", "1 item". The plural rules are compiled as needed from the [CLDR Language Plural Rules](http://www.unicode.org/cldr/charts/26/supplemental/language_plural_rules.html) (which are also used for OrdinalFormat and RangeFormat). All possibilities for a language must be covered in a given translation.

```
{NUM, plural,
  one {One item}
other {# items}}.

# %{num: 1} => "One item."
# %{num: 3} => "3 items."
```

## OrdinalFormat

OrdinalFormat is the same as PluralFormat, but for ordered numbers, e.g. `1st`.

```
You came in {PLACE, ordinal,
                one {#st}
                two {#nd}
                few {#rd}
              other {#th}} place.

# %{place: 2}  => "You came in 2nd place."
# %{place: 12} => "You came in 12th place."
# %{place: 22} => "You came in 22nd place."
```

## RangeFormat

RangeFormat is where you have a range between two numbers, which then needs a plural following it, e.g. `3-5 items`. The possible choices are the same or a subset of the cardinal outputs for the same language. Although in English this is always just `other`, these rules can be much more complicated. For instance, in Czech:

```
{RANGE, range,
    one {# den}
    few {# dny}
   many {# dne}
  other {# dní}}.

# %{range: {0, 1}}      => "0-1 den."
# %{range: {2, 4}}      => "2-4 dny."
# %{range: {2, "3,50"}} => "2-3,50 dne."
# %{range: {0, 5}}      => "0-5 dní."
```

The argument for a range should be a tuple of two numbers {a, b} and will be printed as `a-b`, substituting the `#`.

# Using Polyglot

## Parameters

Parameters for a string should be provided in a map with atom keys. The names are downcased from their definitions inside the translation files. When providing numbers, you can provide any of integer, float or string. If you need a number formatted, especially decimals, you should format them as a string prior to calling.

Polyglot currently has no knowledge of decimal rules, and will treat either `.` or `,` as the decimal separator when found. It is therefore incompatible with numbers formatted with thousands separators such as `1,234.56`.

## Inline string definitions

Perhaps useful when you have very few translations, or just need to test functionality quickly.

```elixir
defmodule I18n do
  use Polyglot

  locale_string "en", "simple", "My simple string."

  locale_string "en", "interpolate", "Hello \#{NAME}."

  locale_string "en", "plural", """
  {NUM, plural,
    one {one item}
  other {# items}}.
  """
end

I18n.t!("en", "simple")
# => "My simple string."

I18n.t!("en", "interpolate", %{name: "Chris"})
# => "Hello Chris."

I18n.t!("en", "plural", %{num: 5})
# => "5 items."
```

## Lang files

Lang files let you package up message definitions together, along with comments. Using special non-code files for translations makes character escaping issues less prominent, and getting new translations made from translators much easier (and the format is simple to parse for integrating into other workflows).

```
This is a comment that precedes the strings.

@test message
Hello from the translator.

-- and this is a comment inbetween strings

@test message 2
{NUM, plural,
    one {one item}
  other {# items}}.
```

```elixir
defmodule I18n do
  use Polyglot

  locale "en", Path.join([__DIR__, "/locales/en.lang"])
end

I18n.t!("en", "test message")
# => "Hello from the translator."

I18n.t!("en", "test message 2", %{num: 5})
# => "5 items."
```

# Roadmap

- [x] Simple variable interpolation
- [x] Lazy plural rule compilation
- [x] Cardinal pluralisation
- [x] Ordinal pluralisation
- [x] Range pluralisation
- [x] Compile from standalone files as well as embedded strings
- [ ] Lint plural/ordinal/range to check cases covered.
- [ ] Lint select cases somehow (maybe by comparing to a canonical language?).
- [x] Accept strings for plural/ordinal/range.
- [x] Deal with differing decimal marks.
- [ ] Utility helpers for number formatting based on locale? (NumberFormat-ish?)
- [ ] Compile to JavaScript.
