package com.duloveni.dshlink

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONObject
import java.net.URI
import java.util.Base64

// Never use a data class here: generated toString() would expose credentials.
class ConnectionProfile private constructor(
    val server: String, val mode: String, val clientId: String, val secret: String, val connectionKey: String
) {
    fun headers() = if (mode == "quick_tunnel") mapOf("Authorization" to "Bearer $connectionKey")
        else mapOf("CF-Access-Client-Id" to clientId, "CF-Access-Client-Secret" to secret)
    fun json() = JSONObject().put("server_url", server).put("auth_mode", mode)
        .put("client_id", clientId).put("client_secret", secret).put("connection_key", connectionKey)
    override fun toString() = "ConnectionProfile(redacted)"
    companion object {
        fun create(server: String, mode: String, id: String = "", secret: String = "", key: String = "", allowLocalTest: Boolean = false): ConnectionProfile {
            val raw = server.trim()
            val uri = runCatching { URI(raw) }.getOrNull()
            val url = raw.toHttpUrlOrNull()
            require(url != null && uri != null && uri.rawUserInfo == null && url.username.isEmpty() && url.password.isEmpty()
                && url.query == null && url.fragment == null && (url.isHttps || (allowLocalTest && url.host == "127.0.0.1"))) { "请填写完整的 HTTPS 地址，不带用户名、查询参数或片段。" }
            require(mode in setOf("access", "quick_tunnel")) { "不支持的连接方式。" }
            fun valid(value: String) = value.length in 1..4096 && value.all { it.code in 33..126 }
            if (mode == "access") require(valid(id.trim()) && valid(secret.trim())) { "请填写有效的 Service Token Client ID 和 Secret。" }
            else require(key.trim().matches(Regex("[a-f0-9]{64}"))) { "连接密钥应为 64 位小写十六进制字符。" }
            return ConnectionProfile(url.toString().trimEnd('/'), mode, if (mode == "access") id.trim() else "",
                if (mode == "access") secret.trim() else "", if (mode == "quick_tunnel") key.trim() else "")
        }
        fun decode(value: JSONObject, allowLocalTest: Boolean = false) = create(value.getString("server_url"), value.optString("auth_mode", "access"),
            value.optString("client_id"), value.optString("client_secret"), value.optString("connection_key"), allowLocalTest)
        fun invitation(raw: String, now: Long = System.currentTimeMillis() / 1000): ConnectionProfile {
            require(raw.toByteArray().size <= 2000) { "二维码过长。" }
            val uri = runCatching { URI(raw) }.getOrNull()
            require(uri?.scheme == "dshremote" && uri.host == "configure" && uri.rawUserInfo == null && uri.port == -1 && uri.path.isNullOrEmpty() && uri.fragment == null) { "这不是 dsh link 的连接二维码。" }
            val query = uri!!.rawQuery ?: ""
            require(query.matches(Regex("data=[A-Za-z0-9_-]+"))) { "二维码格式无效。" }
            val value = try { JSONObject(String(Base64.getUrlDecoder().decode(query.removePrefix("data=")), Charsets.UTF_8)) }
                catch (_: Exception) { throw IllegalArgumentException("二维码内容无效。") }
            val expiry = value.optLong("expires_at", 0)
            require(expiry > now && expiry <= now + 360) { "二维码已过期或时间不正确，请在电脑重新生成。" }
            when (value.optInt("version")) {
                1 -> require(!value.has("auth_mode") && !value.has("connection_key")) { "二维码认证方式冲突。" }
                2 -> require(value.optString("auth_mode") == "quick_tunnel" && !value.has("client_id") && !value.has("client_secret")) { "二维码认证方式冲突。" }
                else -> throw IllegalArgumentException("请更新客户端以支持此二维码。")
            }
            return decode(value)
        }
    }
}
