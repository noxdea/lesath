# ADR 001: Reject unsupported spreadsheet features on import

- Status: Accepted
- Date: 2026-09-24
- Author: Yudai Takada

## Context

Q9-a asks for xlsx/ODS interchange. Rukbat's workbook holds sparse cell input,
formulas, formats, comments, ranges and print metadata, while its CSV route
exports a single sheet with explicit input/calculated-value choice. XLSX and
ODS are package formats with many more features. Reading only visible values
then saving would quietly destroy unsupported content.

## Decision

Lesath has its own small workbook model. Import validates every ZIP part and
supported XML element/attribute. Unknown or unsupported content raises an
error before returning a workbook. Export creates a new package and never
overwrites an existing path. The initial subset contains ordered sheets,
one-based sparse cells, strings, finite numbers, booleans and same-format
formula text with a cached scalar. It does not evaluate formulas. Cross-format
formula export is rejected because SpreadsheetML and OpenFormula use different
syntax and function semantics. Input values are stored separately from
formula text. Formula caches may be stale; callers must recalculate them.

Cell formatting, date/time serial interpretation, rich text, shared formulas,
styles, merged cells, validation, protection, named ranges, drawing/chart
parts, embedded objects, signatures, encryption, macros and external
relationships are outside the subset and rejected. XLSX's default numeric
cell has no date inference; non-default style references are rejected. ODS
supports only `string`, `float`, `boolean` value types. These are explicit
compatibility limits, not an implicit lossy conversion option.

ZIP input is restricted to 256 entries, 20 MiB per part, 50 MiB total and a
1,000:1 advertised compression ratio; paths, duplicate names and encrypted
entries are rejected. XML DTD/entity declarations are rejected before parsing.
Package part allowlists and XML element/attribute allowlists prevent silent
loss of unknown features. This limits supported real-world files, including
many office-generated workbooks with default style or metadata parts. Expand
the subset only with a fixture proving that each added feature survives a
read/write round trip or produces a clear error.

ODS whitespace that requires `text:s`, tabs or line-break markup is rejected
until those elements are supported. XLSX inline strings use `xml:space` when
needed. Public cell text is immutable, and generated packages must pass the
same size and compression checks as imported packages before publication.

The model is intentionally independent of Rukbat. A future adapter should
map only representable values and explicitly reject Rukbat formatting,
comments, named ranges and metadata until those are implemented here. It
must not silently discard them.

## Standards

- [ECMA-376, Office Open XML](https://ecma-international.org/publications-and-standards/standards/ecma-376/) — SpreadsheetML and Open Packaging Conventions.
- [Microsoft Open XML SpreadsheetML structure](https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/structure-of-a-spreadsheetml-document) — workbook, worksheet, relationship and cell packaging examples.
- [OASIS OpenDocument 1.3 Part 2: Packages](https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part2-packages.html) — manifest and uncompressed first `mimetype` entry.
- [OASIS OpenDocument 1.3 Part 3: Schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part3-schema.html) — spreadsheet tables, value types and repeated cells.
- [OASIS OpenDocument 1.3 Part 4: OpenFormula](https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part4-formula.html) — ODS formula syntax.
