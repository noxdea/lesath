# frozen_string_literal: true

require "tmpdir"
require "lesath"

RSpec.describe Lesath do
  def workbook
    Lesath::Workbook.new.tap do |book|
      book.add_sheet("Sales").add_sheet("Résumé")
      book.set("Sales", 1, 1, "Tea & Coffee")
      book.set("Sales", 2, 3, 12.5)
      book.set("Sales", 1_000, 5, false)
      book.set("Résumé", 1, 1, 42)
    end
  end

  %i[xlsx ods].each do |format|
    it "round-trips multiple sparse sheets in #{format}" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "book.#{format}")
        Lesath.write(workbook, path)
        restored = Lesath.read(path)
        expect(restored.sheet_names).to eq(["Sales", "Résumé"])
        expect(restored.cell("Sales", 1, 1).value).to eq("Tea & Coffee")
        expect(restored.cell("Sales", 2, 3).value).to eq(12.5)
        expect(restored.cell("Sales", 1_000, 5).value).to eq(false)
        expect(restored.cell("Résumé", 1, 1).value).to eq(42)
        expect { Lesath.write(workbook, path) }.to raise_error(Lesath::Error, /exists/)
      end
    end

    it "round-trips same-format formula text and cache in #{format}" do
      book = workbook
      expression = format == :xlsx ? "=SUM(C2:C2)" : "of:=SUM([.C2:.C2])"
      book.set("Résumé", 2, 1, 12.5, formula: expression)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "formula.#{format}")
        Lesath.write(book, path)
        cell = Lesath.read(path).cell("Résumé", 2, 1)
        expect([cell.formula, cell.value]).to eq([expression, 12.5])
      end
    end
  end

  it "rejects cross-format formula export" do
    Dir.mktmpdir do |dir|
      book = workbook
      book.set("Sales", 3, 1, 1, formula: "=C2+1")
      xlsx = File.join(dir, "book.xlsx")
      Lesath.write(book, xlsx)
      expect { Lesath.write(Lesath.read(xlsx), File.join(dir, "book.ods")) }.to raise_error(Lesath::UnsupportedFeature)
    end
  end

  it "writes the required uncompressed first ODS mimetype entry" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "book.ods")
      Lesath.write(workbook, path)
      Zip::File.open(path) do |zip|
        expect(zip.entries.first.name).to eq("mimetype")
        expect(zip.entries.first.compression_method).to eq(Zip::Entry::STORED)
      end
    end
  end

  it "rejects unknown ZIP parts rather than losing them" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.xlsx")
      Lesath.write(workbook, source)
      Zip::File.open(source) { |zip| zip.get_output_stream("xl/drawings/drawing1.xml") { |io| io.write("<drawing/>") } }
      expect { Lesath.read(source) }.to raise_error(Lesath::UnsupportedFeature, /parts/)
    end
  end

  it "rejects XML DTDs" do
    expect { Lesath::Package.xml('<!DOCTYPE a [<!ENTITY x "bad">]><a/>') }.to raise_error(Lesath::InvalidPackage, /DTD/)
  end

  it "rejects unsupported cell styles before returning an imported workbook" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "styled.xlsx")
      Lesath.write(workbook, path)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("xl/worksheets/sheet1.xml")
        xml = entry.get_input_stream.read.sub("r='A1'", "r='A1' s='1'")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::UnsupportedFeature, /style/)
    end
  end

  it "rejects invalid XML characters in outgoing values" do
    expect { workbook.set("Sales", 3, 1, "bad\0value") }.to raise_error(Lesath::Error, /XML/)
  end

  it "rejects conflicting ODS value attributes" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "conflict.ods")
      Lesath.write(workbook, path)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("content.xml")
        xml = entry.get_input_stream.read.sub("office:value='12.5'", "office:value='12.5' office:string-value='lost'")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::UnsupportedFeature, /conflicting/)
    end
  end

  it "rejects duplicate and split XLSX cell content instead of losing it" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "book.xlsx")
      book = Lesath::Workbook.new.add_sheet("S")
      book.set("S", 1, 1, "foo")
      Lesath.write(book, path)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("xl/worksheets/sheet1.xml")
        xml = entry.get_input_stream.read.sub("</is>", "</is><is><t>lost</t></is>")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::InvalidPackage, /duplicate/)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("xl/worksheets/sheet1.xml")
        xml = entry.get_input_stream.read.sub("<t>foo</t>", "<t>foo<![CDATA[bar]]>baz</t>")
          .sub("<is><t>lost</t></is>", "")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::UnsupportedFeature, /CDATA/)
    end
  end

  it "requires a cached scalar for imported XLSX formulas" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "book.xlsx")
      book = Lesath::Workbook.new.add_sheet("S")
      book.set("S", 1, 1, "cached", formula: '="text"')
      Lesath.write(book, path)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("xl/worksheets/sheet1.xml")
        xml = entry.get_input_stream.read.sub(/<v>cached<\/v>/, "")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::UnsupportedFeature, /cached value/)
    end
  end

  it "preserves XLSX whitespace and rejects ODS whitespace it cannot encode" do
    Dir.mktmpdir do |dir|
      book = Lesath::Workbook.new.add_sheet("S")
      book.set("S", 1, 1, " a  b ")
      xlsx = File.join(dir, "book.xlsx")
      Lesath.write(book, xlsx)
      Zip::File.open(xlsx) do |zip|
        expect(zip.find_entry("xl/worksheets/sheet1.xml").get_input_stream.read).to include("xml:space='preserve'")
      end
      expect(Lesath.read(xlsx).cell("S", 1, 1).value).to eq(" a  b ")
      expect { Lesath.write(book, File.join(dir, "book.ods")) }
        .to raise_error(Lesath::UnsupportedFeature, /whitespace/)
    end
  end

  it "rejects split ODS text and whitespace that would display differently" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "book.ods")
      book = Lesath::Workbook.new.add_sheet("S")
      book.set("S", 1, 1, "foo")
      Lesath.write(book, path)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("content.xml")
        xml = entry.get_input_stream.read.sub("<text:p>foo</text:p>", "<text:p>foo<![CDATA[bar]]>baz</text:p>")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::UnsupportedFeature, /CDATA/)
      Zip::File.open(path) do |zip|
        entry = zip.find_entry("content.xml")
        xml = entry.get_input_stream.read.sub("<text:p>foo<![CDATA[bar]]>baz</text:p>", "<text:p> foo </text:p>")
          .sub("office:string-value='foo'", "office:string-value=' foo '")
        zip.get_output_stream(entry.name) { |stream| stream.write(xml) }
      end
      expect { Lesath.read(path) }.to raise_error(Lesath::UnsupportedFeature, /whitespace/)
    end
  end

  it "freezes stored text and refuses to write an unreadable package" do
    book = Lesath::Workbook.new.add_sheet("S")
    book.set("S", 1, 1, "safe")
    expect { book.cell("S", 1, 1).value.replace("bad\0value") }.to raise_error(FrozenError)
    expect { book.sheet_names.first.replace("Broken") }.to raise_error(FrozenError)
    expect { book.set("S", 1, 2, "x" * 32_768) }.to raise_error(Lesath::Error, /32767/)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "large.xlsx")
      expect { Lesath::Package.write({"part" => "x" * 2_000_000}, path) }
        .to raise_error(Lesath::InvalidPackage, /compression/)
      expect(File.exist?(path)).to be(false)
    end
  end
end
