namespace java com.coldblossom.darius.archive
namespace rb ColdBlossom.Darius.Archive

const binary MAGIC = "ARH1"
const i32 VERSION = 1

const i32 FORMAT_CODE_TEXT = 0
const i32 FORMAT_CODE_DEFLATE = 1

struct IndexEntry {
  1: string key
  2: i32 offset
  3: i32 length
}

struct IndexSegment {
  1: string name
  2: list<IndexEntry> index_entries
}

struct ContentMetadata {
  1: string key
  2: string value
}

struct ContentSegment {
  1: i32 format_code
  2: list<ContentMetadata> matadata
  3: binary content
}

struct ArchiveFileFormat {
  1: binary magic
  2: i32 version
  3: i32 index_section_length
  4: list<IndexSegment> index_segments
  5: list<ContentSegment> content_segments
}