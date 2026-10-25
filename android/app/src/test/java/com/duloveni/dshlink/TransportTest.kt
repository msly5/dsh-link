package com.duloveni.dshlink

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class TransportTest {
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
