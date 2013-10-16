require_relative 'gen-rb/archive_file_format_types'
require_relative 'gen-rb/archive_file_format_constants'

module ColdBlossom
  module Darius
    module Archive
      class ArchiveFile < ArchiveFileFormat

        def write_to_file(file)
          p self.magic.pack 'cccc'
          file.write self.magic.pack 'cccc'
          len = self.magic.length

          len += write_uint32 self.version, file
          #raise "len: #{len} | file len: #{file.length}" if len != file.length
          len += write_uint32 self.header_length, file

          len += write_header_sections(file)
          self.header_length = len

          p len
          p file.length
          len
        end

        def write_header_sections(file)
          if self.header_sections.nil? or self.header_sections.empty?
            return write_uint32 0, file
          end

          len = write_uint32 self.header_sections.length, file
          self.header_sections.each do |section|
            len += write_string section.name, file
            if section.entries.nil? or section.entries.empty?
              len += write_uint32 0, file
            else
              len += write_uint32 section.entries.length, file
              section.entries.each do |entry|
                len += write_header_section_entry entry, file
              end
            end
          end
          len
        end

        def self.write_bundle(bundle, file)
          archive_file = ArchiveFile.from_bundle bundle
          archive_file.write_to_file file
        end

        def self.from_bundle(bundle)
          a = ArchiveFile.new
          allocate_header a, bundle

          p bundle
          a
        end

        private
        def write_uint32(n, file)
          s = [n].pack 'L'
          file.write s
          p s
          s.length
        end

        def write_string(str, file)
          a = str.bytes
          len = write_uint32 a.length, file
          p a.pack 'c*'
          file.write a.pack 'c*'
          len += a.length
          len
        end

        def write_header_section_entry(entry, file)
          len = write_string entry.key, file
          len += write_uint32 entry.offset, file
          len += write_uint32 entry.length, file
          len
        end


        def self.allocate_header(a, bundle)
          a.magic = MAGIC.bytes
          a.version = VERSION
          a.header_length = -1

          a.header_sections = []
          [{:key => :index_files,
            :name => 'index'},
           {:key => :article_files,
            :name => 'article'}].each do |bundle_section|
            unless bundle[bundle_section[:key]].nil? or bundle[bundle_section[:key]].empty?
              header_section = HeaderSection.new do |section|
                section.name = bundle_section[:name]
                section.entries = []

                bundle[bundle_section[:key]].each do |file|
                  entry = HeaderSectionEntry.new do |entry|
                    entry.key = file[:key]
                    entry.offset = -1
                    entry.length = -1
                  end
                  section.entries << entry
                end

              end
              a.header_sections << header_section
            end
          end
          a
        end

      end
    end
  end
end