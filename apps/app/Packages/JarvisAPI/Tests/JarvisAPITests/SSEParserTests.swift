import Foundation
import Testing
@testable import JarvisAPI

struct SSEParserTests {
    @Test func parsesMultiEventStream() {
        var parser = SSELineParser()
        let stream =
            "event: meta\n" +
            "data: {\"conversationId\":\"conv_1\"}\n" +
            "\n" +
            ": keep-alive comment\n" +
            "event: message_delta\n" +
            "data: {\"text\":\"Hello\"}\n" +
            "\n" +
            "event: message_done\n" +
            "data: {\"messageId\":\"msg_1\",\"conversationId\":\"conv_1\"}\n" +
            "\n"

        let events = parser.feed(stream)
        #expect(events == [
            SSEEvent(event: "meta", data: #"{"conversationId":"conv_1"}"#),
            SSEEvent(event: "message_delta", data: #"{"text":"Hello"}"#),
            SSEEvent(event: "message_done", data: #"{"messageId":"msg_1","conversationId":"conv_1"}"#),
        ])
    }

    @Test func joinsMultiLineDataWithNewline() {
        var parser = SSELineParser()
        let events = parser.feed("data: line one\ndata: line two\n\n")
        #expect(events == [SSEEvent(event: "message", data: "line one\nline two")])
    }

    @Test func defaultsEventNameToMessage() {
        var parser = SSELineParser()
        let events = parser.feed("data: hi\n\n")
        #expect(events == [SSEEvent(event: "message", data: "hi")])
    }

    @Test func handlesChunksSplitMidLine() {
        var parser = SSELineParser()
        var events: [SSEEvent] = []
        events += parser.feed("event: me")
        events += parser.feed("ta\ndata: {\"a\"")
        events += parser.feed(":1}\n")
        #expect(events.isEmpty)
        events += parser.feed("\n")
        #expect(events == [SSEEvent(event: "meta", data: #"{"a":1}"#)])
    }

    @Test func handlesCRLFLineEndings() {
        var parser = SSELineParser()
        let events = parser.feed("event: meta\r\ndata: x\r\n\r\n")
        #expect(events == [SSEEvent(event: "meta", data: "x")])
    }

    @Test func ignoresCommentsAndUnknownFields() {
        var parser = SSELineParser()
        let events = parser.feed(": comment\nid: 42\nretry: 1000\ndata: x\n\n")
        #expect(events == [SSEEvent(event: "message", data: "x")])
    }

    @Test func blankLineWithoutDataDispatchesNothing() {
        var parser = SSELineParser()
        let events = parser.feed("event: meta\n\n\n\n")
        #expect(events.isEmpty)
    }

    @Test func eventNameResetsBetweenEvents() {
        var parser = SSELineParser()
        let events = parser.feed("event: meta\ndata: a\n\ndata: b\n\n")
        #expect(events == [
            SSEEvent(event: "meta", data: "a"),
            SSEEvent(event: "message", data: "b"),
        ])
    }

    @Test func stripsSingleLeadingSpaceFromValueOnly() {
        var parser = SSELineParser()
        // "data:  spaced" — first space is the separator pad, second is data.
        let events = parser.feed("data:  spaced\ndata:unpadded\n\n")
        #expect(events == [SSEEvent(event: "message", data: " spaced\nunpadded")])
    }
}
