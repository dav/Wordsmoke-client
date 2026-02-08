import XCTest
@testable import Wordsmoke

final class APIErrorTests: XCTestCase {
  func testStatusCodeDescriptionUsesValidationDetails() {
    let body = #"{"error":"Validation failed","details":{"phrase":["contains language that is not allowed"]}}"#
    let error = APIError.statusCode(422, body)

    XCTAssertEqual(error.errorDescription, "contains language that is not allowed")
  }

  func testStatusCodeDescriptionFallsBackToMessage() {
    let body = #"{"error":"upgrade_required","message":"Please update to continue."}"#
    let error = APIError.statusCode(426, body)

    XCTAssertEqual(error.errorDescription, "Please update to continue.")
  }
}
