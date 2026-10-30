package com.duloveni.dshlink

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class TransportTest {
    @Test fun suggestionsOnlyMatchCommandNamesBeforeArguments() {
        assertEquals("",SlashCommands.suggestionQuery("/"))
        assertEquals("com",SlashCommands.suggestionQuery("  /Com"))
        for(text in listOf("hello","/compact ","/permission read-only","/tmp/file.txt","//server","`/compact`","/compact\n")) {
            assertNull(text,SlashCommands.suggestionQuery(text))
        }
    }

    @Test fun catalogReadsSessionScopedNativeArrayAndRejectsMalformedResults() = runBlocking {
        val server=MockWebServer();server.start()
        val client=RemoteClient(ConnectionProfile.create(server.url("/").newBuilder().host("127.0.0.1").build().toString(),"quick_tunnel",key="a".repeat(64),allowLocalTest=true))
        try {
            server.enqueue(MockResponse().setBody("""{"result":{"ok":true,"value":[{"name":"permission","description":"Set permissions","input":{"hint":"preset"}},{"name":"compact","description":"Compact history"},{"name":"compact","description":"Duplicate"},{"name":"../bad","description":"Invalid"}]}}"""))
            val catalog=client.commandCatalog("fixture")
            assertEquals(listOf("compact","permission"),catalog.map {it.name});assertEquals("preset",catalog.last().inputHint)
            val request=server.takeRequest()
            assertEquals("/api/commands/list",request.path)
            assertEquals("fixture",org.json.JSONObject(request.body.readUtf8()).child("payload").child("args").getString("agentId"))
            server.enqueue(MockResponse().setBody("""{"result":{"ok":true,"value":{}}}"""))
            try {client.commandCatalog("fixture");fail("Object must not be silently treated as empty catalog")} catch(_:IllegalStateException) { }
            server.takeRequest()
            server.enqueue(MockResponse().setBody("""{"result":{"ok":true,"value":[]}}"""))
            assertTrue(client.commandCatalog("fixture").isEmpty())
        } finally {client.close();server.shutdown()}
    }

    @Test fun commandsUseNativeExecutorAndUnknownCommandsNeverBecomePrompts() = runBlocking {
        val server=MockWebServer(); server.start()
        val client=RemoteClient(ConnectionProfile.create(server.url("/").newBuilder().host("127.0.0.1").build().toString(),"quick_tunnel",key="a".repeat(64),allowLocalTest=true))
        try {
            server.enqueue(MockResponse().setBody("""{"result":{"ok":true,"value":{"commandId":"compact-one","result":{"kind":"success","text":"No compactable history yet."}}}}"""))
            assertEquals(SubmissionKind.COMMAND,client.submit("fixture"," /compact ",emptyList(),"draft"))
            val request=server.takeRequest(); val args=org.json.JSONObject(request.body.readUtf8()).child("payload").child("args")
            assertEquals("/api/commands/execute",request.path)
            assertEquals("fixture",args.getString("agentId")); assertEquals("/compact",args.getString("line"))
            assertEquals(0,args.getJSONArray("submittedAttachments").length())
            for(value in listOf("{}","""{"result":{"kind":"error","text":"Agent is busy"}}""")) {
                server.enqueue(MockResponse().setBody("""{"result":{"ok":true,"value":$value}}"""))
                try {client.submit("fixture","/compact",emptyList(),"draft");fail("Failed command must retain draft")} catch(_:IllegalStateException) { }
                assertEquals("/api/commands/execute",server.takeRequest().path)
                assertNull(server.takeRequest(100,TimeUnit.MILLISECONDS))
            }
        } finally {client.close();server.shutdown()}
    }

    @Test fun pathsAndQuotedCommandsRemainOrdinaryMessages() = runBlocking {
        val server=MockWebServer();server.start()
        val client=RemoteClient(ConnectionProfile.create(server.url("/").newBuilder().host("127.0.0.1").build().toString(),"quick_tunnel",key="a".repeat(64),allowLocalTest=true))
        try {
            for(text in listOf("/tmp/file.txt","//server/share","Explain /compact","`/compact`","/Users")) {
                server.enqueue(MockResponse().setBody("""{"result":{"ok":true,"value":{"accepted":true}}}"""))
                assertEquals(SubmissionKind.PROMPT,client.submit("fixture",text,emptyList(),"stable-draft"))
                val request=server.takeRequest();val r=org.json.JSONObject(request.body.readUtf8()).child("payload").child("args").child("request")
                assertEquals("/api/session/prompt",request.path);assertEquals("stable-draft",r.optString("requestId"))
            }
        } finally {client.close();server.shutdown()}
    }

    @Test fun commandResultsRestoreAndMergeWithTheirOriginalInvocation() {
        val start=obj("type" to "command/run","seq" to 1,"data" to obj("commandId" to "compact-one","name" to "compact","args" to ""))
        val end=obj("type" to "command/done","seq" to 2,"data" to obj("commandId" to "compact-one","kind" to "success","text" to "Compacted 8 items."))
        val rows=Events.merge(Events.parse(start),Events.parse(end))
        assertEquals(1,rows.size);assertEquals("/compact",rows[0].label);assertEquals("Compacted 8 items.",rows[0].text)
        assertEquals("/compact",rows[0].detail);assertEquals(1,rows[0].seq)
    }

    @Test fun redirectsDoNotLeakCredentialsAndRPCEnvelopeIsCorrect() = runBlocking {
        val server=MockWebServer(); val destination=MockWebServer();server.start();destination.start()
        val profile=ConnectionProfile.create(server.url("/").newBuilder().host("127.0.0.1").build().toString(),"quick_tunnel",key="a".repeat(64),allowLocalTest=true)
        val client=RemoteClient(profile)
        try {
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location",destination.url("/stolen")))
            try {client.sessions();fail("Redirect must fail")} catch(e: Exception) {assertTrue(e.message!!.contains("重定向"))}
            assertNull(destination.takeRequest(150,TimeUnit.MILLISECONDS))
            assertEquals("Bearer "+"a".repeat(64),server.takeRequest().getHeader("Authorization"))
            server.enqueue(MockResponse().setBody("{\"result\":{\"ok\":true,\"value\":{\"items\":[]}}}"))
            assertTrue(client.sessions().isEmpty())
            val request=server.takeRequest();val body=org.json.JSONObject(request.body.readUtf8())
            assertEquals("/api/session/list",request.path);assertEquals("client-request",body.getString("type"));assertTrue(body.child("payload").child("args").has("_request"))
        } finally {client.close();server.shutdown();destination.shutdown()}
    }
}
