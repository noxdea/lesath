---
layout: guide
title: Formulas and cached values
description: Preserve formula text and its cached result within the same spreadsheet format.
---

Lesath stores formulas and cached scalar values. It does not evaluate a
formula, verify its result, or translate formula languages. Your application
must supply and maintain the cached value.

**On this page**

* Contents
{:toc}

## XLSX formulas

XLSX formula text starts with `=`. Pass the cached result as the ordinary
cell value:

```ruby
require "lesath"

book = Lesath::Workbook.new.add_sheet("Sales")
book.set("Sales", 1, 1, 12.5)
book.set("Sales", 2, 1, 8.0)
book.set("Sales", 3, 1, 20.5, formula: "=SUM(A1:A2)")

Lesath.write(book, "formula.xlsx")
restored = Lesath.read("formula.xlsx")
cell = restored.cell("Sales", 3, 1)
cell.formula # => "=SUM(A1:A2)"
cell.value   # => 20.5
```

Cached results can be supported strings, finite numbers, or booleans. Always
provide a non-`nil` result. Imported XLSX formulas without a cached scalar
raise `Lesath::UnsupportedFeature`.

## ODS formulas

ODS uses OpenFormula syntax with the prefix `of:=` and its own reference
notation:

```ruby
book = Lesath::Workbook.new.add_sheet("Sales")
book.set("Sales", 1, 1, 12.5)
book.set("Sales", 2, 1, 8.0)
book.set("Sales", 3, 1, 20.5, formula: "of:=SUM([.A1:.A2])")

Lesath.write(book, "formula.ods")
restored = Lesath.read("formula.ods")
cell = restored.cell("Sales", 3, 1)
cell.formula # => "of:=SUM([.A1:.A2])"
cell.value   # => 20.5
```

ODS formula import and export require a cached value. The same ODS string
whitespace restrictions apply to string results.

## Update cached results

Changing an input does not update dependent cells. Update both formula text
and its cached result explicitly:

```ruby
book = Lesath.read("formula.xlsx")
book.set("Sales", 1, 1, 15.0)
book.set("Sales", 3, 1, 23.0, formula: "=SUM(A1:A2)")
Lesath.write(book, "formula-updated.xlsx")
```

If you only change A1, A3 still holds the old cached result. Lesath does not
track dependencies or recalculate the workbook. Formula text is preserved
within the supported syntax; this is not a promise that its cache is current.

## Conversion between formats

An imported workbook containing formulas cannot be exported to the other
format. This raises `Lesath::UnsupportedFeature` because XLSX and ODS use
different formula languages:

```ruby
book = Lesath.read("formula.xlsx")
Lesath.write(book, "formula.ods") # raises Lesath::UnsupportedFeature
```

For a new workbook, formula prefixes must match the export format. Explicitly
selecting a different `format:` does not convert those prefixes or references.

If your application needs only cached values, remove formulas explicitly
before converting. This discards formula text and keeps the current caches:

```ruby
book = Lesath.read("formula.xlsx")
book.sheet_names.each do |sheet|
  book.each_cell(sheet) do |row, column, cell|
    book.set(sheet, row, column, cell.value) if cell.formula
  end
end
Lesath.write(book, "values-only.ods")
```

Do this only when cached values meet your application's needs. They may be
stale, and all values must still satisfy the destination's
[compatibility rules](compatibility.html).
