---
layout: guide
title: Workbook API
description: Create sheets, edit sparse cells, and read or write a workbook.
---

The public entry points are `Lesath.read`, `Lesath.write`, and
`Lesath::Workbook`. The workbook stores sheet names in insertion order and
only allocates populated cells.

**On this page**

* Contents
{:toc}

## Sheets

Create a workbook and add sheets in the order you want to export them:

```ruby
require "lesath"

book = Lesath::Workbook.new
book.add_sheet("Sales").add_sheet("Summary")
book.sheet_names # => ["Sales", "Summary"]
```

Sheet names must contain 1–31 characters and be unique without regard to
case. They cannot contain `[`, `]`, `:`, `*`, `?`, a backslash, or `/`, or begin
or end with an apostrophe. Invalid XML characters are rejected.

`add_sheet` returns the workbook. `sheet_names` returns a frozen array of
frozen names. There is no public sheet rename or removal method.

## Set and read cells

`set(sheet, row, column, value = nil, formula: nil)` creates or replaces a cell
and returns the workbook. Coordinates are integer row and column numbers,
both starting at 1.

```ruby
book.set("Sales", 1, 1, "Tea")
book.set("Sales", 1, 2, 12.5)
book.set("Sales", 1, 3, true)
book.set("Sales", 10, 4, 42)

cell = book.cell("Sales", 1, 2)
cell.value   # => 12.5
cell.formula # => nil
book.cell("Sales", 2, 2) # => nil
book.cell_count          # => 4
```

| Ruby value | Meaning |
| --- | --- |
| `String` | Plain text |
| `Integer` | Integer within the 15-digit precision limit |
| Finite `Float` | Numeric cell |
| `true` or `false` | Boolean cell |
| `nil`, without a formula | Remove the cell |

`Date`, `Time`, `BigDecimal`, arbitrary objects, and non-finite floats are not
accepted. Convert data explicitly at your application's boundary. A numeric
date serial stays a number; Lesath does not infer dates.

Cells are immutable `Lesath::Cell` values with `value` and `formula` readers.
Stored strings and formula text are frozen. To change a cell, call `set`
again. Accessing an unknown sheet raises `Lesath::Error`.

## Clear a cell

Passing `nil` without a formula removes the populated position:

```ruby
book.set("Sales", 1, 3, nil)
book.cell("Sales", 1, 3) # => nil
book.cell_count          # => 3
```

An empty string (`""`) remains a populated string cell. It is different from
an absent cell.

## Iterate over populated cells

`each_cell` yields row, column, and cell in row-major order. Blank positions
are skipped:

```ruby
book.each_cell("Sales") do |row, column, cell|
  puts "#{row},#{column}: #{cell.value.inspect}"
end
# 1,1: "Tea"
# 1,2: 12.5
# 10,4: 42
```

Without a block, it returns an enumerator:

```ruby
values = book.each_cell("Sales").map do |row, column, cell|
  [row, column, cell.value]
end
# => [[1, 1, "Tea"], [1, 2, 12.5], [10, 4, 42]]
```

`cell_count` counts populated cells across all sheets, including formula
cells. An empty sheet is preserved when you write a workbook, but exporting
a workbook with no sheets raises `Lesath::Error`.

## Read, edit, and save

```ruby
book = Lesath.read("sales.xlsx")
book.source_format # => :xlsx

book.set("Sales", 2, 2, 15.0)
Lesath.write(book, "sales-updated.xlsx")
```

`read` returns a workbook only after validating the package and its supported
content. `write` returns the output path. Both accept an optional
`format: :xlsx` or `format: :ods`; otherwise they use the filename extension,
without regard to case.

`source_format` is `:xlsx` or `:ods` for imported workbooks and `nil` for a new
workbook. It helps prevent cross-format formula export; choosing `format:`
does not translate formulas.

Writes require an existing parent directory and a new target path. Lesath
checks generated ZIP packages against the same package limits as imports
before publishing the output. It does not overwrite your source file.

See [formulas and cached values](formulas.html) for formula cells, or
[compatibility and limits](compatibility.html#errors) for handling failures.
