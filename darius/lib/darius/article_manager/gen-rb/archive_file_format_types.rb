#
# Autogenerated by Thrift Compiler (0.9.1)
#
# DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
#

require 'thrift'

module ColdBlossom
  module Darius
    module Archive
      class HeaderSectionEntry
        include ::Thrift::Struct, ::Thrift::Struct_Union
        KEY = 1
        OFFSET = 2
        LENGTH = 3

        FIELDS = {
          KEY => {:type => ::Thrift::Types::STRING, :name => 'key'},
          OFFSET => {:type => ::Thrift::Types::I32, :name => 'offset'},
          LENGTH => {:type => ::Thrift::Types::I32, :name => 'length'}
        }

        def struct_fields; FIELDS; end

        def validate
        end

        ::Thrift::Struct.generate_accessors self
      end

      class HeaderSection
        include ::Thrift::Struct, ::Thrift::Struct_Union
        NAME = 1
        ENTRIES = 2

        FIELDS = {
          NAME => {:type => ::Thrift::Types::STRING, :name => 'name'},
          ENTRIES => {:type => ::Thrift::Types::LIST, :name => 'entries', :element => {:type => ::Thrift::Types::STRUCT, :class => ::ColdBlossom::Darius::Archive::HeaderSectionEntry}}
        }

        def struct_fields; FIELDS; end

        def validate
        end

        ::Thrift::Struct.generate_accessors self
      end

      class ContentMetadata
        include ::Thrift::Struct, ::Thrift::Struct_Union
        KEY = 1
        VALUE = 2

        FIELDS = {
          KEY => {:type => ::Thrift::Types::STRING, :name => 'key'},
          VALUE => {:type => ::Thrift::Types::STRING, :name => 'value'}
        }

        def struct_fields; FIELDS; end

        def validate
        end

        ::Thrift::Struct.generate_accessors self
      end

      class ContentSection
        include ::Thrift::Struct, ::Thrift::Struct_Union
        FORMAT_CODE = 1
        MATADATA = 2
        CONTENT = 3

        FIELDS = {
          FORMAT_CODE => {:type => ::Thrift::Types::I32, :name => 'format_code'},
          MATADATA => {:type => ::Thrift::Types::LIST, :name => 'matadata', :element => {:type => ::Thrift::Types::STRUCT, :class => ::ColdBlossom::Darius::Archive::ContentMetadata}},
          CONTENT => {:type => ::Thrift::Types::STRING, :name => 'content', :binary => true}
        }

        def struct_fields; FIELDS; end

        def validate
        end

        ::Thrift::Struct.generate_accessors self
      end

      class ArchiveFileFormat
        include ::Thrift::Struct, ::Thrift::Struct_Union
        MAGIC = 1
        VERSION = 2
        HEADER_LENGTH = 3
        HEADER_SECTIONS = 4
        CONTENT_SECTION = 5

        FIELDS = {
          MAGIC => {:type => ::Thrift::Types::STRING, :name => 'magic', :binary => true},
          VERSION => {:type => ::Thrift::Types::I32, :name => 'version'},
          HEADER_LENGTH => {:type => ::Thrift::Types::I32, :name => 'header_length'},
          HEADER_SECTIONS => {:type => ::Thrift::Types::LIST, :name => 'header_sections', :element => {:type => ::Thrift::Types::STRUCT, :class => ::ColdBlossom::Darius::Archive::HeaderSection}},
          CONTENT_SECTION => {:type => ::Thrift::Types::LIST, :name => 'content_section', :element => {:type => ::Thrift::Types::STRUCT, :class => ::ColdBlossom::Darius::Archive::ContentSection}}
        }

        def struct_fields; FIELDS; end

        def validate
        end

        ::Thrift::Struct.generate_accessors self
      end

    end
  end
end
