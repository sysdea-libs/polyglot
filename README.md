# MessageFormat

An implementation of MessageFormat (PluralFormat + SelectFormat) in Elixir, for the purposes of translation when plural and gender forms are needed, especially when used together inside sentences ("She found 3 categories in one result").

WIP

# TODO

- [x] Lazy plural rule compilation
- [x] Cardinal pluralisation (default)
- [x] Ordinal pluralisation
- [ ] Range pluralisation
- [ ] Compile from standalone files as well as embedded strings
- [ ] Lint plural and selectordinal to check cases covered.
- [ ] Lint select cases somehow (maybe by comparing to a canonical language?)
