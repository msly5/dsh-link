package com.duloveni.dshlink

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class RemoteClient(val profile: ConnectionProfile, private val transport: OkHttpClient = secureClient()) {
    companion object {
        fun secureClient() = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
            .retryOnConnectionFailure(false).connectTimeout(20,TimeUnit.SECONDS).readTimeout(120,TimeUnit.SECONDS)
            .callTimeout(150,TimeUnit.SECONDS).pingInterval(20,TimeUnit.SECONDS).build()
        fun status(code: Int) = when(code) {
            401,403 -> "鉴权失败，请检查连接密钥或 Service Token。"
            in 300..399 -> "服务器返回重定向，请检查 HTTPS 地址和 Access Service Auth 策略。"
            502,503,504 -> "电脑上的 DSH 不可达，请确认桌面端与桥接正在运行。"
            else -> "请求失败（HTTP $code）。"
        }
    }
    private fun request(path: String): Request.Builder = Request.Builder().url(profile.server + path).apply { profile.headers().forEach { (k,v) -> header(k,v) } }
    suspend fun call(method: String, args: JSONObject = JSONObject()): JSONObject = callValue(method, args) as? JSONObject ?: JSONObject()
    suspend fun commandCatalog(sessionId: String): List<CommandDescriptor> {
        val value = callValue("commands/list", obj("agentId" to sessionId)) as? org.json.JSONArray
            ?: error("指令列表格式异常。")
        return CommandDescriptor.parse(value)
    }
    private suspend fun callValue(method: String, args: JSONObject): Any = suspendCancellableCoroutine { continuation ->
        val body = obj("type" to "client-request", "rpcId" to UUID.randomUUID().toString(), "method" to method, "payload" to obj("args" to args))
        val call = transport.newCall(request("/api/$method").post(body.toString().toRequestBody("application/json".toMediaType())).build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) { if (continuation.isActive) continuation.resumeWithException(IOException("连接失败，请检查网络和电脑端服务。")) }
            override fun onResponse(call: Call, response: Response) {
                val result = runCatching {
                    response.use {
                        check(response.isSuccessful) { status(response.code) }
                        val source = response.body?.source() ?: error("服务器响应为空。")
                        val buffer = okio.Buffer()
                        while (true) {
                            val count = source.read(buffer, 8192)
                            if (count == -1L) break
                            check(buffer.size <= 32 * 1024 * 1024) { "服务器响应过大。" }
                        }
                        val root = try { JSONObject(buffer.readUtf8()) } catch (_: Exception) { error("服务器响应格式异常。") }
                        val result = root.optJSONObject("result") ?: error("服务器响应缺少结果。")
                        if (!result.optBoolean("ok")) error(result.child("error").optString("message", "调用失败。").take(600))
                        result.opt("value") ?: JSONObject.NULL
                    }
                }
                if (continuation.isActive) result.fold({continuation.resume(it)}, {continuation.resumeWithException(it)})
            }
        })
    }
    suspend fun submit(sessionId: String, text: String, images: List<PendingImage>, requestId: String): SubmissionKind {
        val line=text.trim()
        require(line.isNotEmpty() || images.isNotEmpty()) { "请先输入文字或选择图片。" }
        val command=SlashCommands.name(line)
        if(command!=null) {
            val execution=call("commands/execute",obj("agentId" to sessionId,"line" to line,
                "submittedAttachments" to org.json.JSONArray().apply {images.forEach {put(it.content())}}))
            val result=execution.optJSONObject("result") ?: error("未知或格式错误的指令：/$command。")
            check(result.optString("kind")=="success") {result.optString("text").ifBlank {"指令执行失败。"}}
            return SubmissionKind.COMMAND
        }
        val content=org.json.JSONArray().apply {
            if(line.isNotEmpty()) put(obj("type" to "text","text" to line))
            images.forEach {put(it.content())}
        }
        val result=call("session/prompt",obj("request" to obj("requestId" to requestId,"sessionId" to sessionId,
            "mode" to "queue","content" to content,"clientTimeZone" to java.util.TimeZone.getDefault().id)))
        check(result.optBoolean("accepted")) {"服务器未确认接收，输入已保留。"}
        return SubmissionKind.PROMPT
    }
    suspend fun sessions() = call("session/list", obj("_request" to JSONObject())).objects("items").map(Session::parse).sortedByDescending { it.updated }
    fun socket(listener: WebSocketListener) = transport.newWebSocket(request("/api/remote.mux").build(), listener)
    suspend fun workspace(): JSONObject = withTimeout(20000) {
        suspendCancellableCoroutine { continuation ->
            val socket = socket(object: WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.send(obj("type" to "open", "streamId" to "workspaces", "endpoint" to "workspace/follow", "payload" to obj("args" to JSONObject())).toString()) }
                override fun onMessage(webSocket: WebSocket, text: String) {
                    val root = runCatching { JSONObject(text) }.getOrNull() ?: return
                    val frame = root.optJSONObject("value") ?: root
                    if (frame.optString("type") in setOf("baseline","replace") && continuation.isActive) {
                        continuation.resume(frame.child("value")); webSocket.close(1000,"Done")
                    } else if (frame.optString("type") in setOf("error","end") && continuation.isActive) {
                        continuation.resumeWithException(IOException("读取工作区失败。")); webSocket.close(1000,"Done")
                    }
                }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    if (continuation.isActive) continuation.resumeWithException(IOException(response?.let { status(it.code) } ?: "无法连接工作区消息流。"))
                }
            })
            continuation.invokeOnCancellation { socket.cancel() }
        }
    }
    fun close() { transport.dispatcher.cancelAll(); transport.connectionPool.evictAll() }
}
