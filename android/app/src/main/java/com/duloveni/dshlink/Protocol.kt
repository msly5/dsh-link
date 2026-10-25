package com.duloveni.dshlink

import org.json.JSONArray
import org.json.JSONObject

fun obj(vararg values: Pair<String, Any?>) = JSONObject().apply { values.forEach { (k, v) -> put(k, v ?: JSONObject.NULL) } }
fun JSONArray.objects() = (0 until length()).mapNotNull { optJSONObject(it) }
fun JSONArray.strings() = (0 until length()).mapNotNull { opt(it) as? String }
fun JSONObject.objects(key: String) = optJSONArray(key)?.objects().orEmpty()
fun JSONObject.strings(key: String) = optJSONArray(key)?.strings().orEmpty()
fun JSONObject.child(key: String) = optJSONObject(key) ?: JSONObject()

data class Session(val id: String, val title: String, val cwd: String, val running: Boolean, val updated: Long, val values: JSONObject) {
    companion object {
        fun parse(o: JSONObject): Session {
            val values = o.child("projections").child("values")
            return Session(o.getString("sessionId"), values.optString("title").ifBlank { o.optString("cwd").replace('\\','/').substringAfterLast('/').ifBlank { "新对话" } }, o.optString("cwd"), o.optBoolean("running"), o.optLong("updatedAt"), values)
        }
    }
}
data class Workspace(val id: String, val title: String, val path: String, val sessions: List<String>) {
    companion object { fun parse(o: JSONObject) = Workspace(o.getString("workspaceId"), o.optString("title").ifBlank { "工作区" }, o.optString("path"), o.strings("sessionIds")) }
}
data class ChatImage(val id: String, val name: String)
data class ChatRow(val id: String, val seq: Int, val role: String, val text: String, val label: String = "", val detail: String = "", val images: List<ChatImage> = emptyList())
data class PendingImage(val data: ByteArray, val name: String) {
    fun content() = obj("type" to "image", "mediaType" to "image/jpeg", "name" to name, "data" to java.util.Base64.getEncoder().encodeToString(data))
    override fun toString() = "PendingImage(redacted)"
}
object Events {
    fun event(record: JSONObject) = record.optJSONObject("event") ?: record
    fun text(parts: List<JSONObject>, type: String = "text") = parts.filter { it.optString("type") == type }.joinToString("") { it.optString("text") }
    fun stream(parts: List<JSONObject>, kind: String) = parts.joinToString("") {
        when (it.optString("type")) {
            "$kind-chunks" -> it.strings("texts").joinToString("")
            "chunk" -> it.child("chunk").let { c -> if (c.optString("type") == "$kind-delta") c.optString("text") else "" }
            else -> ""
        }
    }
    fun parse(event: JSONObject): List<ChatRow> {
        val type = event.optString("type"); val seq = event.optInt("seq"); val data = event.optJSONObject("data") ?: event
        if (type == "tool/call") {
            val call = data.optString("callId"); if (call.isEmpty()) return emptyList()
            val args = data.opt("arguments")?.toString().orEmpty()
            val argsObject = runCatching { JSONObject(args) }.getOrNull()
            val label = argsObject?.optString("description")?.takeIf { it.isNotBlank() } ?: data.optString("name", "执行工具")
            return listOf(ChatRow("call:$call", seq, "tool", "", label, args))
        }
        val role: String; val parts: List<JSONObject>; var id = "s$seq"; var label = ""
        when (type) {
            "user/message" -> {
                if (data.child("source").optString("kind") in setOf("agent-instructions", "runtime-context", "skill-catalog", "time-context", "system-prompt")) return emptyList()
                role = "user"; parts = data.objects("content")
            }
            "assistant/message" -> { role = "assistant"; parts = data.child("message").objects("content") }
            "tool/result" -> {
                role = "tool"; val message = data.child("message"); parts = message.objects("content")
                val call = message.child("source").optString("callId").ifBlank { message.optString("toolCallId") }
                if (call.isNotEmpty()) id = "call:$call"
                label = if (message.optBoolean("isError")) "执行失败" else "执行结果"
            }
            else -> return emptyList()
        }
        val images = parts.filter { it.optString("type") == "image" }.mapNotNull { p ->
            val ref = p.child("attachment"); ref.optString("attachmentId").takeIf { it.isNotEmpty() }?.let { ChatImage(it, ref.optString("name", "图片")) }
        }
        var text = text(parts)
        if (role == "user") text = text.replace(Regex("(?s)<system-reminder>.*?</system-reminder>"), "").trim()
        val rows = mutableListOf<ChatRow>()
        if (role == "assistant") text(parts, "reasoning").takeIf { it.isNotBlank() }?.let { rows += ChatRow("s$seq-reasoning",seq,"tool",it,"思考") }
        if (text.isNotBlank() || images.isNotEmpty() || role == "tool") rows += ChatRow(id, seq, role, text, label, images=images)
        return rows
    }
    fun merge(old: List<ChatRow>, incoming: List<ChatRow>): List<ChatRow> {
        val map = old.associateBy { it.id }.toMutableMap()
        incoming.forEach { row ->
            val previous = map[row.id]
            map[row.id] = if (previous != null && row.role == "tool") row.copy(seq=previous.seq, label=previous.label.ifBlank { row.label }, detail=previous.detail.ifBlank { row.detail }) else row
        }
        return map.values.sortedWith(compareBy<ChatRow> { it.seq }.thenBy { it.id })
    }
}
