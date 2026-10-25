package com.duloveni.dshlink

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import java.util.Base64

class ProtocolTest {
    private val key="a".repeat(64)
    private fun invitation(value: JSONObject) = "dshremote://configure?data="+Base64.getUrlEncoder().withoutPadding().encodeToString(value.toString().toByteArray())
    private fun rejects(block:()->Unit) {try {block();fail("Expected rejection")} catch(_:IllegalArgumentException) {}}
    @Test fun credentialBindingAndValidation() {
        val p=ConnectionProfile.create("https://EXAMPLE.com:443/", "quick_tunnel",id="ignored",secret="ignored",key=key)
        assertEquals("https://example.com",p.server);assertEquals("",p.secret);assertEquals(setOf("Authorization"),p.headers().keys)
        assertFalse(p.toString().contains(key))
        for(url in listOf("http://example.com","https://user:pass@example.com","https://example.com?x=y","https://example.com#x","https://@example.com")) rejects {ConnectionProfile.create(url,"quick_tunnel",key=key)}
        rejects {ConnectionProfile.create("https://example.com","access","test-id","test\r\nheader")}
        rejects {ConnectionProfile.create("https://example.com","unknown")}
        rejects {ConnectionProfile.create("https://example.com","quick_tunnel",key="short")}
    }
    @Test fun pairingVersionsAndExpiry() {
        val v1=obj("version" to 1,"expires_at" to 1300,"server_url" to "https://example.com","client_id" to "test-id","client_secret" to "test-secret")
        val v2=obj("version" to 2,"expires_at" to 1300,"server_url" to "https://fixture.trycloudflare.com","auth_mode" to "quick_tunnel","connection_key" to key)
        assertEquals("access",ConnectionProfile.invitation(invitation(v1),1000).mode)
        assertEquals("quick_tunnel",ConnectionProfile.invitation(invitation(v2),1000).mode)
        rejects {ConnectionProfile.invitation(invitation(v2),1300)}
        rejects {ConnectionProfile.invitation(invitation(v2),900)}
        rejects {ConnectionProfile.invitation(invitation(v2.put("client_secret","test-secret")),1000)}
        rejects {ConnectionProfile.invitation("dshremote://configure?data=bad&data=bad",1000)}
    }
    @Test fun messageEnvelopeInternalContextAndToolMerge() {
        val record=obj("event" to obj("type" to "user/message","seq" to 1,"data" to obj("source" to obj("kind" to "agent-instructions"),"content" to org.json.JSONArray().put(obj("type" to "text","text" to "private-instructions")))))
        assertTrue(Events.parse(Events.event(record)).isEmpty())
        val tool=Events.parse(obj("type" to "tool/call","seq" to 2,"data" to obj("callId" to "fixture","name" to "bash","arguments" to obj("description" to "Read a file"))))
        val result=Events.parse(obj("type" to "tool/result","seq" to 3,"data" to obj("message" to obj("source" to obj("callId" to "fixture"),"content" to org.json.JSONArray().put(obj("type" to "text","text" to "done"))))))
        val merged=Events.merge(tool,result)
        assertEquals(1,merged.size);assertEquals("Read a file",merged[0].label);assertEquals("done",merged[0].text);assertEquals(2,merged[0].seq)
    }
}
