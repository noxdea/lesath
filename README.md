<h1 align="center">Lesath</h1>

<p align="center">
  <strong>Strict XLSX and ODS spreadsheet interchange for Ruby</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/lesath"><img src="https://img.shields.io/gem/v/lesath.svg" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/lesath"><img src="https://img.shields.io/gem/dt/lesath.svg" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/lesath/actions/workflows/main.yml"><img src="https://github.com/noxdea/lesath/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/CRuby-%3E%3D%203.2-cc342d.svg" alt="CRuby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#supported-subset-and-limits">Limits</a> ·
  <a href="#development">Development</a>
</p>

---

Lesath reads and writes a documented subset of `.xlsx` and `.ods` workbooks.
It preserves supported cell content and rejects unsupported features instead
of silently dropping them. It is a library for spreadsheet interchange, not a
spreadsheet UI or calculation engine. The name comes from Lesath (υ Scorpii),
from Arabic *lasʿa*, “sting.”

## Features

- Read and write XLSX and ODS with multiple ordered sheets and sparse cells.
- Store strings, finite numbers, booleans, and same-format formula text with a
  cached scalar value.
- Reject unsupported package parts, XML content, and spreadsheet features on
  import; refuse to overwrite an existing file on export.

## Installation

Requires CRuby 3.2 or newer:

```sh
gem install lesath
```

## Quick start

```ruby
require "lesath"

book = Lesath::Workbook.new
book.add_sheet("Sales")
book.set("Sales", 1, 1, "Item")
book.set("Sales", 2, 1, "Tea")
book.set("Sales", 2, 2, 12.5)

Lesath.write(book, "sales.xlsx")
copy = Lesath.read("sales.xlsx")
copy.cell("Sales", 2, 2).value # => 12.5
```

Cell coordinates are one-based. `Lesath.read` and `Lesath.write` infer the
format from `.xlsx` or `.ods`; use `format: :xlsx` or `format: :ods` to select it
explicitly. `Lesath.write` raises an error if the target already exists.

## Supported subset and limits

Lesath supports up to 200 sheets, 100,000 populated cells, 1,048,576 rows,
16,384 columns, 15-digit integers, 32,767 UTF-16 units per string, and 31
characters per sheet name. XLSX uses inline strings and simple scalar cached
formulas. ODS supports unstyled scalar cells and repeated *blank* rows and
cells. Both formats retain sheet order and names.

Formula text and its cached value are stored, but never evaluated. XLSX
formulas begin with `=`, ODS formulas with `of:=`. Formula cells require a cached
value, and Lesath rejects formula export to the other format: it does not
translate formula languages. Callers must update cached values after formula
inputs change. Without formulas, supported cells can be written to either format.

Styles, rich text, dates and times, merged cells, comments, charts, images,
macros, validations, hyperlinks, named ranges, external links, and other
unsupported package parts or XML elements are rejected on import with
`Lesath::UnsupportedFeature`. ODS strings that need `<text:s>`, tabs, or line
breaks are also rejected instead of changing their display text. Invalid ZIP
packages, size limits, and XML DTDs raise `Lesath::InvalidPackage`. Generated
files are checked against the same ZIP limits before creating the target
path. This strict subset does not promise round trips for general Excel or
LibreOffice files.

`Rukbat::Workbook` is not directly accepted: its formatting and formula
semantics need an explicit adapter and loss policy. Until then, CSV remains
the broader interchange path. See [ADR 001](docs/adr/001-lossless-subset.md)
for the exact boundary and source standards.

## Development

```sh
bundle install
bundle exec rake spec
gem build --strict lesath.gemspec
```

## License

Lesath is released under the [MIT License](LICENSE.txt).
