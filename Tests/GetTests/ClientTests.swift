// The MIT License (MIT)
//
// Copyright (c) 2021-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
import Mocker
@testable import Get

final class APIClientTests: XCTestCase {
    var client: APIClient!
    
    override func setUp() {
        super.setUp()

        client = APIClient(baseURL: URL(string: "https://api.github.com")) {
            $0.sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
        }
    }
    
    // MARK: Basic Requests
    
    // You don't need to provide a predefined list of resources in your app.
    // You can define the requests inline instead.
    func testDefiningRequestInline() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()
        
        // WHEN
        let user: User = try await client.send(.get("/user")).value
                                               
        // THEN
        XCTAssertEqual(user.login, "kean")
    }
    
    func testResponseMetadata() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()
        
        // WHEN
        let response = try await client.send(Paths.user.get)
                                               
        // THEN the client returns not just the value, but data, original
        // request, and more
        XCTAssertEqual(response.value.login, "kean")
        XCTAssertEqual(response.data.count, 1321)
        XCTAssertEqual(response.request.url, url)
        XCTAssertEqual(response.statusCode, 200)
        let metrics = try XCTUnwrap(response.metrics)
        let transaction = try XCTUnwrap(metrics.transactionMetrics.first)
        XCTAssertEqual(transaction.request.url, URL(string: "https://api.github.com/user")!)
    }
    
    func testCancellingRequests() async throws {
        // Given
        let url = URL(string: "https://api.github.com/users/kean")!
        var mock = Mock.get(url: url, json: "user")
        mock.delay = DispatchTimeInterval.seconds(60)
        mock.register()
        
        // When
        let task = Task {
            try await client.send(.get("/users/kean"))
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
            task.cancel()
        }
        
        // Then
        do {
            let _ = try await task.value
        } catch {
            XCTAssertTrue(error is URLError)
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }
    
    // MARK: Response Types
    
    // func value(for:) -> Decodable
    func testResponseDecodable() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()
        
        // WHEN
        let user: User = try await client.send(.get("/user")).value
                                               
        // THEN returns decoded JSON
        XCTAssertEqual(user.login, "kean")
    }
    
    // func value(for:) -> Decodable
    func testResponseDecodableOptional() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .html, statusCode: 200, data: [
            .get: Data()
        ]).register()
        
        // WHEN
        let user: User? = try await client.send(.get("/user")).value
                                               
        // THEN returns decoded JSON
        XCTAssertNil(user)
    }
    
    // func value(for:) -> Decodable
    func testResponseEmpty() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .html, statusCode: 200, data: [
            .get: Data()
        ]).register()
        
        // WHEN
        try await client.send(.get("/user")).value
    }
        
    // func value(for:) -> Data
    func testResponseData() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .html, statusCode: 200, data: [
            .get: "<h>Hello</h>".data(using: .utf8)!
        ]).register()
        
        // WHEN
        let data: Data = try await client.send(.get("/user")).value
        
        // THEN return unprocessed data (NOT what Data: Decodable does by default)
        XCTAssertEqual(String(data: data, encoding: .utf8), "<h>Hello</h>")
    }
    
    // func value(for:) -> String
    func testResponeString() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 200, data: [
            .get: "hello".data(using: .utf8)!
        ]).register()

        // WHEN
        let text: String = try await client.send(.get("/user")).value
                                               
        // THEN
        XCTAssertEqual(text, "hello")
    }
        
    func testDecodingWithVoidResponse() async throws {
        #if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
        #endif
        
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ]).register()
        
        // WHEN
        let request = Request<Void>.post("/user", body: ["login": "kean"])
        try await client.send(request)
    }
    
    // MARK: - Request Body
    
    func testPassEncodableRequestBody() async throws {
        #if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
        #endif
        
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, arguments in
            guard let body = request.httpBody ?? request.httpBodyStream?.data,
                  let json = try? JSONSerialization.jsonObject(with: body, options: []),
                  let user = json as? [String: Any] else {
                return XCTFail()
            }
            XCTAssertEqual(user["id"] as? Int, 1)
            XCTAssertEqual(user["login"] as? String, "kean")
        }
        mock.register()
        
        // WHEN
        let body = User(id: 1, login: "kean")
        let request = Request<Void>.post("/user", body: body)
        try await client.send(request)
    }
 
    func testPassingNilBody() async throws {
        #if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
        #endif
        
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, arguments in
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.httpBodyStream)
        }
        mock.register()
        
        // WHEN
        let body: User? = nil
        let request = Request<Void>.post("/user", body: body)
        try await client.send(request)
    }
}
