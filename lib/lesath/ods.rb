# frozen_string_literal: true

module Lesath
  module ODS
    OFFICE = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    TABLE = "urn:oasis:names:tc:opendocument:xmlns:table:1.0"
    TEXT = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    OF = "urn:oasis:names:tc:opendocument:xmlns:of:1.2"
    MANIFEST = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    MIME = "application/vnd.oasis.opendocument.spreadsheet"
    module_function

    def read(path)
      parts = Package.read(path)
      raise UnsupportedFeature, "unsupported ODS package parts" unless parts.keys.sort == ["META-INF/manifest.xml", "content.xml", "mimetype"].sort
      raise InvalidPackage, "not an ODS spreadsheet" unless parts["mimetype"] == MIME
      check_manifest(parts.fetch("META-INF/manifest.xml"))
      root = Package.xml(parts.fetch("content.xml"))
      Package.check(root, OFFICE, "document-content", attributes: [[OFFICE, "version"]], children: [[OFFICE, "body"]])
      raise UnsupportedFeature, "unsupported ODS version" unless root.attributes["office:version"] == "1.3"
      body = root.elements.to_a
      raise InvalidPackage, "missing ODS body" unless body.length == 1
      Package.check(body.first, OFFICE, "body", children: [[OFFICE, "spreadsheet"]])
      spreadsheet = body.first.elements.to_a
      raise InvalidPackage, "missing ODS spreadsheet" unless spreadsheet.length == 1
      Package.check(spreadsheet.first, OFFICE, "spreadsheet", children: [[TABLE, "table"]])
      book = Workbook.new(source_format: :ods)
      spreadsheet.first.elements.each { |table| parse_table(table, book) }
      raise InvalidPackage, "ODS has no sheets" if book.sheet_names.empty?
      book
    end

    def write(book, path)
      raise Error, "workbook has no sheets" if book.sheet_names.empty?
      raise UnsupportedFeature, "cannot translate xlsx formulas to ODS" if book.source_format == :xlsx && book.sheet_names.any? { |name| book.each_cell(name).any? { |_r, _c, cell| cell.formula } }
      parts = {
        "mimetype" => MIME,
        "META-INF/manifest.xml" => manifest_xml,
        "content.xml" => content_xml(book)
      }
      Package.write(parts, path, first_stored: "mimetype")
    end

    def check_manifest(bytes)
      root = Package.xml(bytes)
      Package.check(root, MANIFEST, "manifest", attributes: [[MANIFEST, "version"]], children: [[MANIFEST, "file-entry"]])
      entries = root.elements.to_a.to_h do |entry|
        Package.check(entry, MANIFEST, "file-entry", attributes: [[MANIFEST, "full-path"], [MANIFEST, "media-type"]])
        [entry.attributes["manifest:full-path"], entry.attributes["manifest:media-type"]]
      end
      raise InvalidPackage, "duplicate ODS manifest entry" if entries.length != root.elements.to_a.length
      raise UnsupportedFeature, "unsupported ODS manifest" unless entries == {"/" => MIME, "content.xml" => "text/xml"}
    end

    def parse_table(element, book)
      Package.check(element, TABLE, "table", attributes: [[TABLE, "name"]], children: [[TABLE, "table-row"]])
      name = element.attributes["table:name"]
      raise InvalidPackage, "missing sheet name" unless name
      book.add_sheet(name)
      row_number = 1
      element.elements.each do |row|
        Package.check(row, TABLE, "table-row", attributes: [[TABLE, "number-rows-repeated"]], children: [[TABLE, "table-cell"]])
        repeat = count(row.attributes["table:number-rows-repeated"])
        raise InvalidPackage, "row out of range" if row_number + repeat - 1 > Workbook::MAX_ROWS
        column_number = 1
        row.elements.each do |cell|
          Package.check(cell, TABLE, "table-cell", attributes: [[TABLE, "number-columns-repeated"], [TABLE, "formula"], [OFFICE, "value-type"], [OFFICE, "value"], [OFFICE, "boolean-value"], [OFFICE, "string-value"]], children: [[TEXT, "p"]])
          columns = count(cell.attributes["table:number-columns-repeated"])
          raise InvalidPackage, "column out of range" if column_number + columns - 1 > Workbook::MAX_COLUMNS
          formula = cell.attributes["table:formula"]
          raise UnsupportedFeature, "unsupported ODS formula syntax" if formula && !formula.start_with?("of:=")
          raise InvalidPackage, "OpenFormula namespace is not bound" if formula && cell.namespace("of") != OF
          value = parse_value(cell)
          raise UnsupportedFeature, "ODS formula requires a cached value" if formula && value.nil?
          populated = !value.nil? || formula
          raise UnsupportedFeature, "repeated populated rows are not supported" if repeat > 1 && populated
          raise UnsupportedFeature, "repeated populated cells are not supported" if columns > 1 && populated
          book.set(name, row_number, column_number, value, formula:) if populated
          column_number += columns
        end
        row_number += repeat
      end
    end

    def parse_value(cell)
      paragraphs = cell.elements.to_a
      paragraphs.each { |paragraph| Package.check(paragraph, TEXT, "p", text: true) }
      raise UnsupportedFeature, "multiline or rich text is not supported" if paragraphs.length > 1 || paragraphs.any? { |p| !p.elements.to_a.empty? }
      type = cell.attributes["office:value-type"]
      values = %w[value boolean-value string-value].select { |key| cell.attributes["office:#{key}"] }
      allowed = {nil => [], "string" => ["string-value"], "float" => ["value"], "boolean" => ["boolean-value"]}[type]
      raise UnsupportedFeature, "unsupported ODS value type: #{type}" unless allowed
      raise UnsupportedFeature, "conflicting ODS value attributes" unless (values - allowed).empty?
      case type
      when nil
        raise InvalidPackage, "text without a value type" unless paragraphs.empty?
        nil
      when "string"
        text = cell.attributes["office:string-value"] || paragraphs.first&.text.to_s
        raise UnsupportedFeature, "ODS string display text is required" if paragraphs.empty?
        safe_text!(text)
        raise InvalidPackage, "string cache differs from display text" if paragraphs.any? && paragraphs.first.text.to_s != text
        text
      when "float"
        raise UnsupportedFeature, "formatted numeric display text" unless paragraphs.empty?
        XLSX.number(cell.attributes["office:value"])
      when "boolean"
        raise UnsupportedFeature, "formatted boolean display text" unless paragraphs.empty?
        {"true" => true, "false" => false}.fetch(cell.attributes["office:boolean-value"]) { raise InvalidPackage, "invalid ODS boolean" }
      end
    end

    def count(value)
      return 1 unless value
      raise InvalidPackage, "invalid repeat count" unless value.length <= 7 && value.match?(/\A[1-9]\d*\z/)
      Integer(value, 10)
    end

    def manifest_xml
      root = REXML::Element.new("manifest:manifest")
      root.add_attributes("xmlns:manifest" => MANIFEST, "manifest:version" => "1.3")
      root.add_element("manifest:file-entry").add_attributes("manifest:full-path" => "/", "manifest:media-type" => MIME)
      root.add_element("manifest:file-entry").add_attributes("manifest:full-path" => "content.xml", "manifest:media-type" => "text/xml")
      Package.render(root)
    end

    def content_xml(book)
      root = REXML::Element.new("office:document-content")
      root.add_attributes("xmlns:office" => OFFICE, "xmlns:table" => TABLE, "xmlns:text" => TEXT, "xmlns:of" => OF, "office:version" => "1.3")
      spreadsheet = root.add_element("office:body").add_element("office:spreadsheet")
      book.sheet_names.each do |name|
        table = spreadsheet.add_element("table:table", {"table:name" => name})
        previous_row = 0
        book.each_cell(name).group_by(&:first).each do |row, cells|
          gap = row - previous_row - 1
          table.add_element("table:table-row", {"table:number-rows-repeated" => gap.to_s}) if gap.positive?
          row_node = table.add_element("table:table-row")
          previous_column = 0
          cells.each do |_row, column, cell|
            raise UnsupportedFeature, "ODS formula must start with of:=" if cell.formula && !cell.formula.start_with?("of:=")
            gap = column - previous_column - 1
            row_node.add_element("table:table-cell", {"table:number-columns-repeated" => gap.to_s}) if gap.positive?
            node = row_node.add_element("table:table-cell")
            node.add_attribute("table:formula", cell.formula) if cell.formula
            case cell.value
            when String
              safe_text!(cell.value)
              node.add_attributes("office:value-type" => "string", "office:string-value" => cell.value)
              node.add_element("text:p").text = cell.value
            when TrueClass, FalseClass then node.add_attributes("office:value-type" => "boolean", "office:boolean-value" => cell.value.to_s)
            when Numeric then node.add_attributes("office:value-type" => "float", "office:value" => cell.value.to_s)
            when NilClass
              raise UnsupportedFeature, "ODS formula requires a cached value" if cell.formula
            end
            previous_column = column
          end
          previous_row = row
        end
      end
      Package.render(root)
    end

    def safe_text!(text)
      if text.match?(/\A | \z| {2}|[\t\r\n]/)
        raise UnsupportedFeature, "ODS string whitespace needs text:s, tab, or line-break support"
      end
    end
  end
end
