# frozen_string_literal: true

module Lesath
  class Error < StandardError; end
  class UnsupportedFeature < Error; end
  class InvalidPackage < Error; end

  Cell = Data.define(:value, :formula)

  class Workbook
    MAX_ROWS = 1_048_576
    MAX_COLUMNS = 16_384
    MAX_CELLS = 100_000
    MAX_SHEETS = 200

    attr_reader :source_format

    def initialize(source_format: nil)
      @source_format = source_format
      @sheets = {}
    end

    def sheet_names = @sheets.keys.freeze

    def add_sheet(name)
      name = xml_text(name.to_s)
      raise Error, "invalid sheet name" if name.empty? || name.length > 31 || name.match?(/[\[\]:*?\\\/]/) || name.start_with?("'") || name.end_with?("'")
      raise Error, "duplicate sheet name: #{name}" if @sheets.keys.any? { |key| key.casecmp?(name) }
      raise Error, "too many sheets" if @sheets.length >= MAX_SHEETS

      @sheets[name.freeze] = {}
      self
    end

    def cell(sheet, row, column)
      @sheets.fetch(sheet) { raise Error, "unknown sheet: #{sheet}" }[[row, column]]
    end

    def set(sheet, row, column, value = nil, formula: nil)
      cells = @sheets.fetch(sheet) { raise Error, "unknown sheet: #{sheet}" }
      raise Error, "cell coordinates out of range" unless row.is_a?(Integer) && row.between?(1, MAX_ROWS) && column.is_a?(Integer) && column.between?(1, MAX_COLUMNS)
      raise Error, "unsupported cell value" unless value.nil? || value.is_a?(String) || value == true || value == false || value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      raise Error, "integer exceeds spreadsheet precision" if value.is_a?(Integer) && value.abs > 999_999_999_999_999
      raise Error, "invalid formula" if formula && (!formula.is_a?(String) || formula.empty?)
      value = xml_text(value) if value.is_a?(String)
      formula = xml_text(formula) if formula
      raise Error, "cell text exceeds 32767 UTF-16 units" if value.is_a?(String) && value.encode("UTF-16LE").bytesize / 2 > 32_767
      raise Error, "too many cells" if !cells.key?([row, column]) && cell_count >= MAX_CELLS

      value.nil? && formula.nil? ? cells.delete([row, column]) : cells[[row, column]] = Cell.new(value:, formula:)
      self
    end

    def each_cell(sheet, &block)
      return enum_for(__method__, sheet) unless block

      @sheets.fetch(sheet) { raise Error, "unknown sheet: #{sheet}" }.sort.each do |(row, column), cell|
        block.call(row, column, cell)
      end
      self
    end

    def cell_count = @sheets.values.sum(&:size)

    private

    def xml_text(value)
      text = value.encode(Encoding::UTF_8)
      raise Error, "invalid XML text" unless text.valid_encoding? && !text.match?(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/)
      text.freeze
    rescue EncodingError
      raise Error, "invalid XML text"
    end
  end
end
