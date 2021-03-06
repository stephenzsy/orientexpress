namespace java com.coldblossom.darius
namespace rb ColdBlossom.Darius

const i32 MAJOR_VERSION = 1
const i32 MINOR_VERSION = 1
const i32 PATCH_VERSION = 0

enum StatusCode {
  UNKNOWN,
  SUCCESS,
  ERROR, // when user input is invalid
  FAULT, // when server encouters a error
  SCHEDULED, // when requested resource is scheduled
  UNAVAILABLE, // when requested resource is unavailable
  BATCHED // when request resource is no longer available through standalone means
}

enum OutputType {
  S3_ARN,
  JSON,
  TEXT
}

enum DocumentType {
  ARTICLE,
  DAILY_ARCHIVE_INDEX,
  RSS_FEED
}

enum DocumentFlavor {
  RAW,
  PROCESSED_JSON
}

enum CacheOption {
  DEFAULT, // will attempt to get from cache if cache did not expire by default criteria
  NO_CACHE, // will not attempt to get a cached copy or refresh the cache
  ONLY_CACHE, // will only attempt cache without refresh
  REFRESH // force refresh the cache
}

exception ServiceException {
  1: StatusCode statusCode,
  2: string message
}

struct GetDocumentRequest {
  1: string vendor,
  2: DocumentType documentType,
  3: DocumentFlavor flavor,
  4: string documentUrl,
  5: string datetime,
  6: OutputType outputType,
  7: CacheOption cacheOption
}

struct GetDocumentResult {
  1: StatusCode statusCode,
  2: string timestamp,
  3: string document
}

enum ArchiveSource {
  NONE,
  CACHE,
  SOURCE,
  EXTERNAL
}

struct GetArchiveRequest {
  1: string vendor,
  2: DocumentFlavor flavor,
  3: string date,
  4: optional ArchiveSource archiveSource
}

struct GetArchiveResult {
  1: StatusCode statusCode,
  2: string resource // S3 ARN
}

service ArticleManager {

  string health()

  list<i32> version()

  GetDocumentResult getDocument(1: GetDocumentRequest request) throws (1: ServiceException e)

  GetArchiveResult getArchive(1: GetArchiveRequest request) throws (1: ServiceException e)
}
