# frozen_string_literal: true

module Lesath
  module XLSX
    MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    DOC_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships"
    TYPES = "http://schemas.openxmlformats.org/package/2006/content-types"
    WORKBOOK_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    SHEET_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
    module_function

    def read(path)
      parts = Package.read(path)
      root_rels(parts.fetch("_rels/.rels") { raise InvalidPackage, "missing root relationships" })
      relationships = workbook_rels(parts.fetch("xl/_rels/workbook.xml.rels") { raise InvalidPackage, "missing workbook relationships" })
      workbook_xml = parts.fetch("xl/workbook.xml") { raise InvalidPackage, "missing workbook" }
      names = workbook_sheets(workbook_xml)
      expected = ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels"]
      book = Workbook.new(source_format: :xlsx)
      names.each do |name, id|
        target = relationships.delete(id) { raise InvalidPackage, "sheet relationship missing: #{id}" }
        expected << target
        book.add_sheet(name)
        parse_sheet(parts.fetch(target) { raise InvalidPackage, "sheet part missing: #{target}" }, book, name)
      end
      raise UnsupportedFeature, "unused workbook relationship" unless relationships.empty?
      raise UnsupportedFeature, "unsupported package parts: #{(parts.keys - expected).join(', ')}" unless (parts.keys - expected).empty?
      content_types(parts.fetch("[Content_Types].xml"), expected)
      book
    end

    def write(book, path)
      raise Error, "workbook has no sheets" if book.sheet_names.empty?
      raise UnsupportedFeature, "cannot translate ODS formulas to xlsx" if book.source_format == :ods && book.sheet_names.any? { |name| book.each_cell(name).any? { |_r, _c, cell| cell.formula } }

      parts = {}
      parts["[Content_Types].xml"] = types_xml(book.sheet_names.length)
      parts["_rels/.rels"] = relationships_xml([["rId1", WORKBOOK_REL, "xl/workbook.xml"]])
      parts["xl/workbook.xml"] = workbook_xml(book.sheet_names)
      parts["xl/_rels/workbook.xml.rels"] = relationships_xml(book.sheet_names.each_index.map { |index| ["rId#{index + 1}", SHEET_REL, "worksheets/sheet#{index + 1}.xml"] })
      book.sheet_names.each_with_index { |name, index| parts["xl/worksheets/sheet#{index + 1}.xml"] = sheet_xml(book, name) }
      Package.write(parts, path)
    end

    def root_rels(bytes)
      root = Package.xml(bytes)
      Package.check(root, PKG_REL, "Relationships", children: [[PKG_REL, "Relationship"]])
      rels = root.elements.to_a
      raise InvalidPackage, "invalid root relationships" unless rels.length == 1
      rel = Package.check(rels.first, PKG_REL, "Relationship", attributes: [["", "Id"], ["", "Type"], ["", "Target"]])
      raise UnsupportedFeature, "unsupported root relationship" unless rel.attributes["Type"] == WORKBOOK_REL && rel.attributes["Target"] == "xl/workbook.xml"
    end

    def workbook_rels(bytes)
      root = Package.xml(bytes)
      Package.check(root, PKG_REL, "Relationships", children: [[PKG_REL, "Relationship"]])
      relationships = root.elements.to_a.to_h do |rel|
        Package.check(rel, PKG_REL, "Relationship", attributes: [["", "Id"], ["", "Type"], ["", "Target"]])
        raise UnsupportedFeature, "unsupported workbook relationship" unless rel.attributes["Type"] == SHEET_REL
        target = rel.attributes["Target"]
        raise UnsupportedFeature, "unsafe worksheet relationship" unless target&.match?(/\Aworksheets\/sheet\d+\.xml\z/)
        [rel.attributes["Id"], "xl/#{target}"]
      end
      raise InvalidPackage, "duplicate workbook relationship" if relationships.length != root.elements.to_a.length
      relationships
    end

    def workbook_sheets(bytes)
      root = Package.xml(bytes)
      Package.check(root, MAIN, "workbook", children: [[MAIN, "sheets"], [MAIN, "calcPr"]])
      sheets = root.elements.to_a.select { |element| element.name == "sheets" }
      raise InvalidPackage, "missing sheets" unless sheets.length == 1
      root.elements.to_a.select { |element| element.name == "calcPr" }.each do |element|
        Package.check(element, MAIN, "calcPr", attributes: [["", "fullCalcOnLoad"]])
      end
      Package.check(sheets.first, MAIN, "sheets", children: [[MAIN, "sheet"]])
      names = sheets.first.elements.to_a.map do |sheet|
        Package.check(sheet, MAIN, "sheet", attributes: [["", "name"], ["", "sheetId"], [DOC_REL, "id"]])
        [sheet.attributes["name"], sheet.attributes["r:id"]]
      end
      raise InvalidPackage, "workbook has no sheets" if names.empty? || names.any? { |name, id| !name || !id }
      names
    end

    def content_types(bytes, expected)
      root = Package.xml(bytes)
      Package.check(root, TYPES, "Types", children: [[TYPES, "Default"], [TYPES, "Override"]])
      overrides = root.elements.to_a.filter_map do |element|
        if element.name == "Default"
          Package.check(element, TYPES, "Default", attributes: [["", "Extension"], ["", "ContentType"]])
          raise UnsupportedFeature, "unsupported content type" unless element.attributes["Extension"] == "rels" && element.attributes["ContentType"] == "application/vnd.openxmlformats-package.relationships+xml"
          nil
        else
          Package.check(element, TYPES, "Override", attributes: [["", "PartName"], ["", "ContentType"]])
          part = element.attributes["PartName"].to_s.delete_prefix("/")
          expected_type = part == "xl/workbook.xml" ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml" : "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
          raise UnsupportedFeature, "unsupported part content type" unless element.attributes["ContentType"] == expected_type
          part
        end
      end
      raise UnsupportedFeature, "content types do not match workbook parts" unless overrides.sort == (expected - ["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels"]).sort
    end

    def parse_sheet(bytes, book, name)
      root = Package.xml(bytes)
      Package.check(root, MAIN, "worksheet", children: [[MAIN, "sheetData"]])
      data = root.elements.to_a
      raise InvalidPackage, "missing sheet data" unless data.length == 1
      Package.check(data.first, MAIN, "sheetData", children: [[MAIN, "row"]])
      data.first.elements.each do |row|
        Package.check(row, MAIN, "row", attributes: [["", "r"]], children: [[MAIN, "c"]])
        row.elements.each { |cell| parse_cell(cell, book, name) }
      end
    end

    def parse_cell(element, book, name)
      Package.check(element, MAIN, "c", attributes: [["", "r"], ["", "t"], ["", "s"]], children: [[MAIN, "f"], [MAIN, "v"], [MAIN, "is"]])
      raise InvalidPackage, "duplicate cell child" if element.elements.to_a.map(&:name).tally.values.any? { |count| count > 1 }
      raise UnsupportedFeature, "cell style is not supported" if element.attributes["s"] && element.attributes["s"] != "0"
      reference = element.attributes["r"]
      raise InvalidPackage, "invalid cell reference" unless reference&.match?(/\A[A-Z]+[1-9]\d*\z/)
      letters, row = reference.match(/\A([A-Z]+)(\d+)\z/).captures
      column = letters.bytes.reduce(0) { |value, byte| value * 26 + byte - 64 }
      row = row.to_i
      raise InvalidPackage, "cell outside row" unless element.parent.attributes["r"].to_i == row
      raise InvalidPackage, "duplicate cell: #{reference}" if book.cell(name, row, column)
      formula = element.elements["f"]
      value = element.elements["v"]
      inline = element.elements["is"]
      Package.check(formula, MAIN, "f", text: true) if formula
      Package.check(value, MAIN, "v", text: true) if value
      if inline
        Package.check(inline, MAIN, "is", children: [[MAIN, "t"]])
        raise UnsupportedFeature, "rich text is not supported" unless inline.elements.to_a.length == 1
        Package.check(inline.elements[1], MAIN, "t", attributes: [["http://www.w3.org/XML/1998/namespace", "space"]], text: true)
        if whitespace_sensitive?(inline.elements[1].text.to_s) && inline.elements[1].attributes["xml:space"] != "preserve"
          raise UnsupportedFeature, "inline string needs xml:space=preserve"
        end
      end
      raise InvalidPackage, "conflicting cell values" if inline && value
      type = element.attributes["t"] || "n"
      parsed = case type
      when "inlineStr" then inline&.elements&.[]("t")&.text.to_s
      when "str" then value&.text.to_s
      when "b" then {"1" => true, "0" => false}.fetch(value&.text) { raise InvalidPackage, "invalid boolean" }
      when "n" then value ? number(value.text) : nil
      else raise UnsupportedFeature, "unsupported cell type: #{type}"
      end
      raise InvalidPackage, "missing inline string" if type == "inlineStr" && !inline
      raise InvalidPackage, "unexpected inline string" if type != "inlineStr" && inline
      raise UnsupportedFeature, "inline formula is not supported" if formula && inline
      raise InvalidPackage, "empty formula" if formula && formula.text.to_s.empty?
      raise UnsupportedFeature, "formula requires a cached value" if formula && !value
      raise UnsupportedFeature, "formula requires a cached value" if formula && parsed.nil?
      book.set(name, row, column, parsed, formula: formula && "=#{formula.text}")
    end

    def number(text)
      raise InvalidPackage, "invalid number" unless text&.match?(/\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\z/)
      value = text.match?(/\A[+-]?\d+\z/) ? Integer(text, 10) : Float(text)
      raise InvalidPackage, "non-finite number" unless value.finite?
      value
    end

    def relationships_xml(entries)
      root = REXML::Element.new("Relationships")
      root.add_attribute("xmlns", PKG_REL)
      entries.each do |id, type, target|
        rel = root.add_element("Relationship")
        rel.add_attributes("Id" => id, "Type" => type, "Target" => target)
      end
      Package.render(root)
    end

    def types_xml(count)
      root = REXML::Element.new("Types")
      root.add_attribute("xmlns", TYPES)
      root.add_element("Default").add_attributes("Extension" => "rels", "ContentType" => "application/vnd.openxmlformats-package.relationships+xml")
      root.add_element("Override").add_attributes("PartName" => "/xl/workbook.xml", "ContentType" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml")
      count.times do |index|
        root.add_element("Override").add_attributes("PartName" => "/xl/worksheets/sheet#{index + 1}.xml", "ContentType" => "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml")
      end
      Package.render(root)
    end

    def workbook_xml(names)
      root = REXML::Element.new("workbook")
      root.add_attributes("xmlns" => MAIN, "xmlns:r" => DOC_REL)
      sheets = root.add_element("sheets")
      names.each_with_index { |name, index| sheets.add_element("sheet").add_attributes("name" => name, "sheetId" => (index + 1).to_s, "r:id" => "rId#{index + 1}") }
      root.add_element("calcPr").add_attribute("fullCalcOnLoad", "1")
      Package.render(root)
    end

    def sheet_xml(book, name)
      root = REXML::Element.new("worksheet")
      root.add_attribute("xmlns", MAIN)
      data = root.add_element("sheetData")
      previous = nil
      book.each_cell(name) do |row, column, cell|
        raise UnsupportedFeature, "xlsx formula must start with =" if cell.formula && !cell.formula.start_with?("=")
        current = row == previous ? data.elements.to_a.last : data.add_element("row", {"r" => row.to_s})
        previous = row
        node = current.add_element("c", {"r" => reference(row, column)})
        node.add_element("f").text = cell.formula.delete_prefix("=") if cell.formula
        case cell.value
        when String
          if cell.formula
            node.add_attribute("t", "str")
            node.add_element("v").text = cell.value
          else
            node.add_attribute("t", "inlineStr")
            text = node.add_element("is").add_element("t")
            text.add_attribute("xml:space", "preserve") if whitespace_sensitive?(cell.value)
            text.text = cell.value
          end
        when TrueClass, FalseClass
          node.add_attribute("t", "b")
          node.add_element("v").text = cell.value ? "1" : "0"
        when Numeric then node.add_element("v").text = cell.value.to_s
        end
      end
      Package.render(root)
    end

    def reference(row, column)
      letters = +""
      while column.positive?
        column, remainder = (column - 1).divmod(26)
        letters.prepend((65 + remainder).chr)
      end
      "#{letters}#{row}"
    end

    def whitespace_sensitive?(text)
      text.match?(/\A\s|\s\z|[ \t]{2}|[\r\n\t]/)
    end
  end
end
