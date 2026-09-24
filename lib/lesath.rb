# frozen_string_literal: true

require "rexml/document"
require "zip"
require_relative "lesath/version"
require_relative "lesath/workbook"
require_relative "lesath/package"
require_relative "lesath/xlsx"
require_relative "lesath/ods"

module Lesath
  def self.read(path, format: nil)
    format ||= File.extname(path).downcase.delete_prefix(".").to_sym
    codec(format).read(path)
  end

  def self.write(workbook, path, format: nil)
    format ||= File.extname(path).downcase.delete_prefix(".").to_sym
    codec(format).write(workbook, path)
  end

  def self.codec(format)
    {xlsx: XLSX, ods: ODS}.fetch(format) { raise ArgumentError, "format must be :xlsx or :ods" }
  end
  private_class_method :codec
end
