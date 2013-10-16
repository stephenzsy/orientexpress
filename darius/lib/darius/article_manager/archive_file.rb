require 'zlib'

require_relative 'gen-rb/archive_file_format_types'
require_relative 'gen-rb/archive_file_format_constants'

module ColdBlossom
  module Darius
    module Archive
      class ArchiveFile < ArchiveFileFormat

        def initialize
          @bundle_map = {}
          self.header_sections ||= []
          self.content_sections ||= []
        end

        def set_bundle_file(key, index_entry, file)
          @bundle_map[key] = {
              :index => index_entry,
              :handle => file
          }
        end

        def write_to_file(file)
          file_pos_origin = file.pos
          p self.magic.pack 'cccc'
          file.write self.magic.pack 'cccc'
          len = self.magic.length
          len += write_uint32 self.version, file

          header_offset = len
          len += write_uint32 self.header_length, file
          len += write_header_sections(file)
          self.header_length = len - header_offset

          len += write_uint32 self.content_sections.length, file
          self.content_sections.each do |content_section|
            section_offset = len
            section_length = write_content_section content_section, file
            len += section_length
            @bundle_map[content_section.key][:index].offset = section_offset
            @bundle_map[content_section.key][:index].length = section_length
          end

          # backfill fields
          file.seek file_pos_origin, IO::SEEK_SET
          file.seek 8, IO::SEEK_CUR #magic and version
          backfill_header_sections file

          file.seek 4, IO::SEEK_CUR # content_sections size
          self.content_sections.each do |content_section|

          end

          p self.header_sections
          p self.content_sections
          p len
          p file.length
          len
        end

        def self.write_bundle(bundle, file)
          archive_file = ArchiveFile.from_bundle bundle
          archive_file.write_to_file file
        end

        def self.from_bundle(bundle)
          a = ArchiveFile.new
          allocate_header a, bundle
        end


        def write_header_sections(file)
          len = write_uint32 self.header_sections.length, file
          self.header_sections.each do |section|
            len += write_string section.name, file
            section.entries ||= []
            len += write_uint32 section.entries.length, file
            section.entries.each do |entry|
              len += write_header_section_entry entry, file
            end
          end
          len
        end

        def backfill_header_sections(file)
          file.seek 4, IO::SEEK_CUR
          self.header_sections.each do |section|
            file.seek(4 + section.name.bytesize() + 4, IO::SEEK_CUR)
            section.entries.each do |entry|
              backfill_header_section_entry entry, file
            end

          end
        end

        def write_content_section(section, file)
          len = 0
          len += write_uint32 section.section_length, file
          section_offset = len
          len += write_uint32 section.section_header_length, file # header_length
          section_header_offset = len
          len += write_uint32 section.format_code, file
          len += write_string section.key, file

          len += write_uint32 section.metadata.size, file
          section.metadata.each do |k, v|
            len += write_string k, file
            len += write_string v, file
          end
          section.section_header_length = len - section_header_offset

          len += write_file_as_deflate @bundle_map[section.key][:handle], file
          section.section_length = len - section_offset

          len
        end

        def write_file_as_deflate(source_file, target_file)
          source_data = File.read source_file
          target_data = Zlib::Deflate.deflate(source_data)
          len = 0
          len += write_uint32 target_data.length, target_file
          target_file.write target_data
          len += target_data.length
          len
        end

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

        def backfill_header_section_entry(entry, file)
          file.seek(4 + entry.key.bytesize, IO::SEEK_CUR)
          write_uint32 entry.offset, file
          write_uint32 entry.length, file
        end


        def self.allocate_header(a, bundle)
          a.magic = MAGIC.bytes
          a.version = VERSION
          a.header_length = -1

          a.header_sections = []
          a.content_sections = []
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
                    a.set_bundle_file entry.key, entry, file[:handle]

                    a.content_sections << ContentSection.new do |content_section|
                      content_section.section_length = -1
                      content_section.section_header_length = -1
                      content_section.key = entry.key
                      content_section.format_code = Archive::FORMAT_CODE_DEFLATE
                      content_section.metadata = {}
                      file[:metadata].each do |k, v|
                        content_section.metadata[k] = v
                      end
                      content_section.content = nil
                    end
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