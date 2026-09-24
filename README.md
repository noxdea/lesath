# Lesath

Lesath (υ Scorpii) is a small library for strict spreadsheet interchange.
The star's name comes from Arabic *lasʿa*, “sting.” It reads and writes a
documented subset of `.xlsx` and `.ods` with no UI or calculation engine.

```ruby
require "lesath"

book = Lesath::Workbook.new
book.add_sheet("Sales").add_sheet("Summary")
book.set("Sales", 1, 1, "Item")
book.set("Sales", 2, 1, "Tea")
book.set("Sales", 2, 2, 12.5)
Lesath.write(book, "sales.xlsx")
copy = Lesath.read("sales.xlsx")
copy.cell("Sales", 2, 2).value # => 12.5
```

Coordinates are one-based. `Lesath.read` / `Lesath.write` infer the format from
the filename or accept `format: :xlsx` / `format: :ods`. Writing refuses to
replace an existing target. The API stores formula text and its cached scalar;
it does not calculate or translate formulas. XLSX formulas begin with `=`, ODS
formulas with `of:=`. A workbook containing formulas cannot be written to the
other format. ODS formulas need a cached value. The caller must recalculate
before exporting changed formula inputs.

Supported cells are strings, finite integers/floats, booleans and empty cells,
with up to 100,000 populated cells, 200 sheets, 1,048,576 rows, 16,384
columns, 15-digit integers, 32,767 UTF-16 units per string and 31 characters per sheet name. XLSX inline strings and simple scalar cached
formulas are supported. ODS unstyled scalar cells and simple repeated blank
rows/cells are supported. Multiple sheets retain their order and names.
ODS strings needing `<text:s>`, tabs or line breaks are rejected rather than
exported with altered display text. Outputs are checked against the same ZIP
limits as imports before being moved to the target path.

Imported files containing cell styles, rich text, dates/times, merged cells,
comments, charts, images, macros, validations, hyperlinks, named ranges,
external links, other unsupported package parts or XML elements raise
`Lesath::UnsupportedFeature`. ZIP and XML limits raise
`Lesath::InvalidPackage`. This is deliberately not a general Excel/LibreOffice
round-trip editor. See [ADR 001](docs/adr/001-lossless-subset.md) for the exact
boundary and source standards.

`Rukbat::Workbook` is not directly accepted: it has richer formatting and
formula semantics, so an adapter must explicitly choose a loss policy. CSV
remains the appropriate broad interchange path until that adapter exists.

```sh
bundle install
bundle exec rake spec
gem build --strict lesath.gemspec
```
