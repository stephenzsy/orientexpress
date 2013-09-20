namespace java com.coldblossom.darius
namespace rb ColdBlossom.Darius

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

enum SchedulingOption {
  DEFAULT, // will attempt to get from cache, if not, schedule to get the requested resource
  NONE, // will not atttempt to schedule to get the requested resource and fail the call directly
  IMMEDIATELY // synchronized call
}

enum CacheOption {
  DEFAULT, // will attempt to get from cache if cache did not expire by default criteria
  NO_CACHE, // will not attempt to get a cached copy or refresh the cache
  ONLY_CACHE, // will only attempt cache without refresh
  REFRESH // force refresh the cache
}

struct GetOriginalDocumentRequest {
  1: string vendor,
  2: DocumentType documentType,
  3: string documentUrl,
  4: string datetime,
  5: OutputType outputType,
  6: SchedulingOption schedulingOption,
  7: CacheOption cacheOption
}

struct GetOriginalDocumentResult {
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

  string version()

  GetOriginalDocumentResult getOriginalDocument(1: GetOriginalDocumentRequest request) throws (1: ServiceException e)

}

