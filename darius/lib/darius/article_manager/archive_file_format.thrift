namespace java com.coldblossom.darius.archive
namespace rb ColdBlossom.Darius.Archive

const binary MAGIC = "ARH1"
const i32 VERSION = 1

const i32 FORMAT_CODE_TEXT = 0
const i32 FORMAT_CODE_DEFLATE = 1

struct HeaderSectionEntry {
  1: string key
  2: i32 offset
  3: i32 length
}

struct HeaderSection {
  1: string name
  2: list<HeaderSectionEntry> entries
}

struct ContentMetadata {
  1: string key
  2: string value
}

struct ContentSection {
  1: i32 format_code
  2: list<ContentMetadata> matadata
  3: binary content
}

struct ArchiveFileFormat {
  1: binary magic
  2: i32 version
  3: i32 header_length
  4: list<HeaderSection> header_sections
  5: list<ContentSection> content_section
}