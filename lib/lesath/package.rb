# frozen_string_literal: true

require "tempfile"

module Lesath
  module Package
    MAX_PART = 20 * 1024 * 1024
    MAX_TOTAL = 50 * 1024 * 1024
    MAX_ENTRIES = 256

    def self.read(path)
      Zip::File.open(path) do |zip|
        raise InvalidPackage, "too many ZIP entries" if zip.entries.length > MAX_ENTRIES

        parts = {}
        total = 0
        zip.entries.each do |entry|
          name = entry.name
          raise InvalidPackage, "unsafe ZIP path" if name.start_with?("/") || name.include?("\\") || name.split("/").include?("..") || name.include?("\0")
          raise InvalidPackage, "duplicate ZIP part: #{name}" if parts.key?(name)
          raise InvalidPackage, "encrypted ZIP entry" if (entry.gp_flags & 1) != 0
          raise InvalidPackage, "ZIP part too large" if entry.size > MAX_PART || total + entry.size > MAX_TOTAL
          raise InvalidPackage, "suspicious ZIP compression" if entry.compressed_size.positive? && entry.size > entry.compressed_size * 1_000

          bytes = entry.get_input_stream { |input| input.read(MAX_PART + 1) }
          raise InvalidPackage, "ZIP part too large" if bytes.bytesize > MAX_PART
          total += bytes.bytesize
          raise InvalidPackage, "ZIP package too large" if total > MAX_TOTAL
          parts[name] = bytes
        end
        parts
      end
    rescue Zip::Error, SystemCallError => error
      raise InvalidPackage, "cannot read package: #{error.message}"
    end

    def self.write(parts, path, first_stored: nil)
      raise Error, "target already exists: #{path}" if File.exist?(path)

      target = File.expand_path(path)
      Tempfile.create([".lesath-", ".tmp"], File.dirname(target)) do |file|
        file.close
        Zip::OutputStream.open(file.path) do |zip|
          parts.each do |name, bytes|
            zip.put_next_entry(name, nil, nil, first_stored == name ? Zip::Entry::STORED : Zip::Entry::DEFLATED)
            zip.write(bytes)
          end
        end
        read(file.path) # An output must satisfy the same ZIP limits as an input.
        if Gem.win_platform?
          created = completed = false
          begin
            File.open(target, File::WRONLY | File::CREAT | File::EXCL) do |output|
              created = true
              IO.copy_stream(file.path, output)
              output.flush
              output.fsync
            end
            completed = true
          ensure
            File.unlink(target) if created && !completed && File.file?(target)
          end
        else
          File.link(file.path, target)
        end
      end
      path
    rescue Errno::EEXIST
      raise Error, "target already exists: #{path}"
    end

    def self.xml(bytes)
      raise InvalidPackage, "XML DTD is not supported" if bytes.match?(/<!\s*(?:DOCTYPE|ENTITY)/i)
      document = REXML::Document.new(bytes)
      raise InvalidPackage, "empty XML part" unless document.root
      document.children.each do |child|
        next if child.is_a?(REXML::XMLDecl) || child.equal?(document.root)
        next if child.is_a?(REXML::Text) && child.value.strip.empty?

        raise UnsupportedFeature, "unsupported XML prolog content"
      end

      document.root
    rescue REXML::ParseException => error
      raise InvalidPackage, "invalid XML: #{error.message}"
    end

    def self.check(element, namespace, name, attributes: [], children: [], text: false)
      raise UnsupportedFeature, "unexpected XML element: #{element.expanded_name}" unless element.namespace == namespace && element.name == name

      element.attributes.each_attribute do |attribute|
        next if attribute.expanded_name == "xmlns" || attribute.expanded_name.start_with?("xmlns:")
        namespace = attribute.expanded_name == "xml:space" ? "http://www.w3.org/XML/1998/namespace" : attribute.namespace
        raise UnsupportedFeature, "unsupported attribute: #{attribute.expanded_name}" unless attributes.include?([namespace, attribute.name])
      end
      element.elements.each do |child|
        raise UnsupportedFeature, "unsupported XML element: #{child.expanded_name}" unless children.include?([child.namespace, child.name])
      end
      text_nodes = element.children.select { |child| child.is_a?(REXML::Text) }
      if text_nodes.any? { |child| child.is_a?(REXML::CData) } || (text && text_nodes.length > 1)
        raise UnsupportedFeature, "CDATA or split XML text is not supported"
      end
      element.children.each do |child|
        if child.is_a?(REXML::Text)
          raise UnsupportedFeature, "unexpected XML text" if !text && !child.value.strip.empty?
        elsif !child.is_a?(REXML::Element)
          raise UnsupportedFeature, "unsupported XML content"
        end
      end
      element
    end

    def self.render(root)
      document = REXML::Document.new
      document << REXML::XMLDecl.new("1.0", "UTF-8")
      document.add_element(root)
      document.to_s
    end
  end
end
