---
layout: guide
title: Getting started
description: Install Lesath and read and write your first spreadsheet in Ruby.
permalink: /docs/
---

Lesath reads and writes a strict subset of XLSX and ODS workbooks. It preserves
supported cells and rejects features it cannot preserve. Use it for controlled
spreadsheet interchange where unsupported content must produce an error.

General Excel and LibreOffice files often contain styles or metadata outside
this subset. Check [compatibility and limits](compatibility.html) before using
Lesath with existing files.

**On this page**

* Contents
{:toc}

## Install

You need CRuby 3.2 or newer. Install the gem:

```sh
gem install lesath
```

For a Bundler application, add it to your Gemfile:

```ruby
gem "lesath"
```

Then run `bundle install`. Lesath is a Ruby library; call it from your Ruby
program or IRB. It does not provide a command-line spreadsheet application.

## Create a workbook

Save this example as `sales.rb` and run `ruby sales.rb` (or
`bundle exec ruby sales.rb` in a Bundler application):

```ruby
require "lesath"

book = Lesath::Workbook.new
book.add_sheet("Sales")
book.set("Sales", 1, 1, "Item")
book.set("Sales", 1, 2, "Amount")
book.set("Sales", 2, 1, "Tea")
book.set("Sales", 2, 2, 12.5)
book.set("Sales", 3, 1, "Coffee")
book.set("Sales", 3, 2, 8.0)

Lesath.write(book, "sales.xlsx")
restored = Lesath.read("sales.xlsx")

puts restored.sheet_names.inspect          # => ["Sales"]
puts restored.cell("Sales", 2, 2).value    # => 12.5
```

Rows and columns start at 1, so `(1, 1)` is A1 and `(2, 2)` is B2. Add a sheet
before assigning its cells. Empty positions do not need to be allocated.

`Lesath.write` creates a new file and refuses to overwrite an existing one.
Choose a new output path before running the example again.

## Write ODS instead

The filename extension selects the format. To produce an ODS file from the
same scalar workbook:

```ruby
Lesath.write(book, "sales.ods")
copy = Lesath.read("sales.ods")
copy.cell("Sales", 2, 2).value # => 12.5
```

You can also read a supported XLSX file and save its scalar cells as ODS:

```ruby
book = Lesath.read("sales.xlsx")
Lesath.write(book, "converted.ods")
```

Cross-format conversion requires cells that the destination can represent.
Formulas are not translated, and ODS has stricter string whitespace rules.
See [formulas and cached values](formulas.html) and
[compatibility and limits](compatibility.html).

## Choose a format explicitly

Use a symbol when the filename does not have a recognized extension:

```ruby
Lesath.write(book, "spreadsheet.data", format: :xlsx)
restored = Lesath.read("spreadsheet.data", format: :xlsx)
```

Only `:xlsx` and `:ods` are accepted. An unsupported extension or format
raises `ArgumentError`.

Continue with the [Workbook API](usage.html) to edit cells, enumerate data,
and inspect an imported workbook.
