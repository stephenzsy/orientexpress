namespace java com.coldblossom.darius
namespace rb ColdBlossom.Darius

const i32 MAJOR_VERSION = 1
const i32 MINOR_VERSION = 0
const i32 PATCH_VERSION = 0

enum StatusCode {
  UNKNOWN,
  SUCCESS,
  ERROR, // when user input is invalid
  FAULT, // when server encouters a error
  SCHEDULED, // when requested resource is scheduled
  UNAVAILABLE // when requested resource is unavailable
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

exception ServiceException {
  1: StatusCode statusCode,
  2: string message
}

service ArticleManager {

  string health()

  list<i32> version()

  GetDocumentResult getDocument(1: GetDocumentRequest request) throws (1: ServiceException e)

}

