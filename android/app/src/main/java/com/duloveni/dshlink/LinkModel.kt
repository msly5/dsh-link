package com.duloveni.dshlink

import android.app.Application
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class LinkModel(app: Application) : AndroidViewModel(app) {
    private val store = ProfileStore(app)
    var profile by mutableStateOf<ConnectionProfile?>(null); private set
    var sessions by mutableStateOf<List<Session>>(emptyList()); private set
    var workspaces by mutableStateOf<List<Workspace>>(emptyList()); private set
    var archived by mutableStateOf<Set<String>>(emptySet()); private set
    var selected by mutableStateOf<Session?>(null); private set
    var rows by mutableStateOf<List<ChatRow>>(emptyList()); private set
    var liveText by mutableStateOf(""); private set
    var reasoning by mutableStateOf(""); private set
    var connected by mutableStateOf(false); private set
    var running by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var sending by mutableStateOf(false); private set
    var loadingHistory by mutableStateOf(false); private set
    var hasMore by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var pending by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var answering by mutableStateOf(false); private set
    var catalog by mutableStateOf(JSONObject()); private set
    var permissions by mutableStateOf<List<JSONObject>>(emptyList()); private set
    var values by mutableStateOf(JSONObject()); private set
    var draft by mutableStateOf("")
    var images by mutableStateOf<List<PendingImage>>(emptyList())
    private var client: RemoteClient? = null
    private var socket: WebSocket? = null
    private var active = true
    private var generation = 0
    private var profileRevision = 0
    private var retry: Job? = null
    private var timeout: Job? = null
    private var retryCount = 0
    private var cursor = -1
    private var historyCursor = -1
    private var streamRevision = 0
    private var nextIndex = 0
    private var attempt = ""
    private var clientId = ""
    private val seenEvents = mutableSetOf<String>()
    private val cache = mutableMapOf<String, List<ChatRow>>()
    private val drafts = mutableMapOf<String, Pair<String, List<PendingImage>>>()
    private var activityRevision = 0
    private var promptId = ""
    private var promptText = ""
    private var promptImages: List<PendingImage> = emptyList()
    init {
        try { store.load()?.let { switchProfile(it) } } catch (e: Exception) { error = e.message }
    }
    private fun failure(e: Throwable) { if (e !is CancellationException) error = e.message?.take(600) ?: "操作失败，请重试。" }
    fun saveProfile(value: ConnectionProfile) { try { store.save(value); switchProfile(value) } catch (e: Exception) { failure(e) } }
    fun clearProfile() { try { store.clear(); switchProfile(null) } catch (e: Exception) { failure(e) } }
    private fun switchProfile(value: ConnectionProfile?) {
        profileRevision++; stopSocket(); client?.close(); client = value?.let(::RemoteClient); profile = value
        sessions=emptyList(); workspaces=emptyList(); archived=emptySet(); selected=null; rows=emptyList()
        cache.clear(); drafts.clear(); draft=""; images=emptyList(); pending=emptyList(); error=null; busy=false
        catalog=JSONObject(); permissions=emptyList(); values=JSONObject(); sending=false; loadingHistory=false
        refresh()
    }
    fun refresh() {
        val api = client ?: return
        if (busy) return
        val revision = profileRevision
        busy = true
        viewModelScope.launch {
            try {
                val (items, snapshot) = coroutineScope {
                    val list = async { api.sessions() }; val workspace = async { api.workspace() }
                    list.await() to workspace.await()
                }
                if (revision != profileRevision) return@launch
                sessions=items; workspaces=snapshot.objects("items").map(Workspace::parse); archived=snapshot.strings("archivedSessionIds").toSet()
                selected?.let { current -> selected=items.find { it.id==current.id } ?: current }
            } catch (e: Exception) { if (revision==profileRevision) failure(e) }
            finally { if (revision==profileRevision) busy=false }
        }
    }
    fun select(session: Session?) {
        selected?.let { drafts[it.id]=draft to images; cache[it.id]=rows }
        stopSocket(); selected=session; pending=emptyList(); seenEvents.clear(); error=null; liveText=""; reasoning=""
        rows=session?.let { cache[it.id] }.orEmpty(); draft=session?.let { drafts[it.id]?.first }.orEmpty(); images=session?.let { drafts[it.id]?.second }.orEmpty()
        cursor=-1; historyCursor=-1; hasMore=false; loadingHistory=false; sending=false; answering=false; running=session?.running==true; values=session?.values ?: JSONObject()
        if (session != null) { connect(); loadCatalogs() }
    }
    fun setActive(value: Boolean) {
        active=value
        if (!value) { selected?.let { cache[it.id]=rows }; stopSocket() }
        else { refresh(); if (selected!=null && socket==null) connect() }
    }
    private fun stopSocket() { generation++; retry?.cancel(); timeout?.cancel(); val old=socket; socket=null; old?.cancel(); connected=false; clientId=""; sending=false; answering=false; loadingHistory=false }
    fun reconnect() { stopSocket(); retryCount=0; connect() }
    private fun connect() {
        if (!active) return
        val api=client ?: return; val session=selected ?: return
        val token=++generation
        connected=false; clientId=""; seenEvents.clear(); pending=emptyList(); streamRevision=0; nextIndex=0; attempt=""
        fun accept(block: () -> Unit) { viewModelScope.launch { if (token==generation) block() } }
        socket=api.socket(object: WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) { webSocket.send(obj("type" to "open","streamId" to "events","endpoint" to "\$events","payload" to obj("args" to JSONObject())).toString()) }
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (text.length>32*1024*1024) { accept { disconnect(token) }; return }
                val root=runCatching { JSONObject(text) }.getOrNull() ?: return
                accept { handle(root.optJSONObject("value") ?: root, session.id, token) }
            }
            override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) { onMessage(webSocket, bytes.utf8()) }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { accept { error=response?.let { RemoteClient.status(it.code) } ?: "连接已断开，正在重连…"; disconnect(token) } }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { accept { disconnect(token) } }
        })
        timeout?.cancel(); timeout=viewModelScope.launch { delay(25000); if (token==generation && !connected) { error="连接超时，正在重试…"; disconnect(token) } }
    }
    private fun disconnect(token: Int) {
        if (token!=generation) return
        stopSocket(); if (!active) return
        retry=viewModelScope.launch { delay((1000L shl retryCount.coerceAtMost(4))); retryCount++; connect() }
    }
    private fun handle(value: JSONObject, sessionId: String, token: Int) {
        when(value.optString("type")) {
            "ready" -> {
                if (clientId.isNotEmpty()) return
                clientId=value.optString("clientId")
                socket?.send(obj("type" to "open","streamId" to "follow","endpoint" to "session/follow","payload" to obj("args" to obj("request" to obj("address" to obj("kind" to "session","sessionId" to sessionId),"maxMessages" to 30,"assistantStream" to true)))).toString())
            }
            "snapshot" -> {
                val records=value.objects("records").map(Events::event); val incoming=records.flatMap(Events::parse)
                val first=records.minOfOrNull { it.optInt("seq") }; val oldCursor=cursor
                cursor=value.optInt("cursor",-1); historyCursor=cursor
                rows=if (value.optBoolean("hasMore") && first!=null && oldCursor>=0 && cursor>=oldCursor && first<=oldCursor+1)
                    Events.merge(rows.filter { it.seq<first },incoming) else Events.merge(emptyList(),incoming)
                hasMore=value.optBoolean("hasMore") && (rows.minOfOrNull { it.seq } ?: 0)>0
                values=value.child("projections").child("values")
                records.forEach(::activity)
                val baseline=value.child("assistantStream"); val activeAttempt=baseline.child("activeAttempt")
                streamRevision=baseline.optInt("revision"); nextIndex=activeAttempt.optInt("nextIndex"); attempt=activeAttempt.optString("attemptId")
                liveText=Events.stream(activeAttempt.objects("stream"),"text"); reasoning=Events.stream(activeAttempt.objects("stream"),"reasoning")
                if (attempt.isNotEmpty()) running=true
                connected=true; retryCount=0; error=null; timeout?.cancel()
            }
            "event" -> {
                val event=value.child("event"); val seq=event.optInt("seq",cursor+1); if (seq<=cursor) return
                cursor=seq; activity(event); rows=Events.merge(rows,Events.parse(event))
                if (event.optString("type")=="assistant/message") { liveText=""; reasoning="" }
            }
            "assistant-stream" -> {
                val frame=value.child("frame"); val type=frame.optString("type")
                if (type=="start" && frame.optInt("revision")==1) streamRevision=0
                val revision=frame.optInt("revision",streamRevision+1)
                if (revision<=streamRevision) return
                if (revision!=streamRevision+1) { reconnect(); return }; streamRevision=revision
                when(type) {
                    "start" -> { attempt=frame.optString("attemptId"); nextIndex=0; liveText=""; reasoning=""; running=true }
                    "chunk" -> {
                        if (frame.has("attemptId") && frame.optString("attemptId")!=attempt) return
                        if (frame.has("index") && frame.optInt("index")!=nextIndex) { reconnect(); return }
                        nextIndex++; val chunk=frame.child("chunk")
                        when(chunk.optString("type")) { "text-delta" -> liveText+=chunk.optString("text"); "reasoning-delta" -> reasoning+=chunk.optString("text") }
                    }
                    "end" -> attempt=""
                }
            }
            "waterfall" -> {
                val id=value.optString("eventId"); if (id.isEmpty() || !seenEvents.add(id)) return
                if (value.optString("agentId")!=sessionId || value.optString("event") !in setOf("approval/request","user-questions/request")) {
                    val api=client ?: return; val identity=clientId
                    viewModelScope.launch { runCatching { api.call("\$events/result",obj("clientId" to identity,"eventId" to id,"outcome" to obj("kind" to "next"))) } }
                } else pending=pending+value
            }
            "cancel" -> pending=pending.filterNot { it.optString("eventId")==value.optString("eventId") }
            "emit" -> { val args=value.optJSONArray("args"); if (value.optString("event")=="api-session/status" && args?.optString(0)==sessionId) { activityRevision++; running=args.optBoolean(1) } }
            "error","end" -> { error="消息流已断开，正在重连…"; disconnect(token) }
        }
    }
    private fun activity(event: JSONObject) { if(event.optString("type") in setOf("turn/start","step/start","turn/end")) activityRevision++; when(event.optString("type")) { "turn/start","step/start" -> running=true; "turn/end" -> { running=false; liveText=""; reasoning=""; refresh() } } }
    private fun loadCatalogs() {
        val api=client ?: return; val revision=profileRevision
        viewModelScope.launch {
            try { val models=api.call("session/modelCatalog"); if (revision==profileRevision) catalog=models } catch (_: Exception) { }
            try { val presets=api.call("permissionPresets/catalog"); if (revision==profileRevision) permissions=presets.objects("options") } catch (_: Exception) { }
        }
    }
    fun create(workspace: Workspace) {
        val api=client ?: return; val revision=profileRevision
        viewModelScope.launch {
            try {
                val id=UUID.randomUUID().toString()
                val result=api.call("session/create",obj("request" to obj("workspaceId" to workspace.id,"sessionId" to id)))
                if (revision!=profileRevision) return@launch
                select(Session(result.getString("sessionId"),"新对话",workspace.path,false,System.currentTimeMillis(),JSONObject())); refresh()
            } catch(e: Exception) { if (revision==profileRevision) failure(e) }
        }
    }
    fun archive(session: Session, archive: Boolean) {
        val api=client ?: return; val revision=profileRevision
        viewModelScope.launch {
            try {
                val req=obj("sessionId" to session.id); if (archive && session.running) req.put("stopActivity",true)
                val result=api.call(if (archive) "workspace/archiveSession" else "workspace/unarchiveSession",obj("request" to req))
                if (revision!=profileRevision) return@launch
                archived=result.strings("archivedSessionIds").toSet(); if (archive && selected?.id==session.id) select(null); refresh()
            } catch(e: Exception) { if (revision==profileRevision) failure(e) }
        }
    }
    fun send() {
        val api=client ?: return; val id=selected?.id ?: return
        if (sending || !connected || (draft.isBlank() && images.isEmpty())) return
        val text=draft.trim(); val attachments=images; val token=generation
        val limits=values.child("imageLimits")
        if (attachments.size>limits.optInt("maxImagesPerMessage",4) || attachments.sumOf { it.data.size }>limits.optInt("maxMessageImageBytes",20*1024*1024) || attachments.any { it.data.size>limits.optInt("maxImageBytes",5*1024*1024) }) { error="图片超过服务器限制，请减少图片数量。"; return }
        if (promptId.isEmpty() || text!=promptText || attachments!=promptImages) { promptId=UUID.randomUUID().toString(); promptText=text; promptImages=attachments }
        val requestId=promptId
        val activityAtSend=activityRevision
        sending=true; error=null
        viewModelScope.launch {
            try {
                val content=JSONArray(); if (text.isNotEmpty()) content.put(obj("type" to "text","text" to text)); attachments.forEach { content.put(it.content()) }
                val result=api.call("session/prompt",obj("request" to obj("requestId" to requestId,"sessionId" to id,"mode" to "queue","content" to content,"clientTimeZone" to java.util.TimeZone.getDefault().id)))
                check(result.optBoolean("accepted")) { "服务器未确认接收，输入已保留。" }
                if (token==generation) { draft=""; images=emptyList(); promptId=""; if(activityAtSend==activityRevision) running=true; drafts.remove(id) }
            } catch(e: Exception) { if (token==generation) failure(e) }
            finally { if (token==generation) sending=false }
        }
    }
    fun cancel() = action { api, id -> api.call("session/cancel",obj("request" to obj("sessionId" to id))) }
    fun chooseModel(provider: String, model: String, effort: String?) = action { api,id ->
        val req=obj("sessionId" to id,"provider" to provider,"model" to model); effort?.let { req.put("reasoningEffort",it) }
        api.call("session/selectModel",obj("request" to req))
        if (client===api && selected?.id==id) values=JSONObject(values.toString()).put("modelSelection",obj("next" to req))
    }
    fun permission(preset: String) = action { api,id ->
        val result=api.call("commands/execute",obj("agentId" to id,"line" to "/permission $preset","submittedAttachments" to JSONArray()))
        check(result.child("result").optString("kind")=="success") { "权限切换失败。" }
        if (client===api && selected?.id==id) values=JSONObject(values.toString()).put("permissions",obj("currentValue" to preset))
    }
    private fun action(block: suspend (RemoteClient,String)->Unit) {
        val api=client ?: return; val id=selected?.id ?: return; val token=generation
        viewModelScope.launch { try { block(api,id) } catch(e: Exception) { if (token==generation) failure(e) } }
    }
    fun answer(value: Any) {
        val api=client ?: return; val first=pending.firstOrNull() ?: return; val token=generation
        if (!connected || answering || clientId.isEmpty()) return
        val identity=clientId; answering=true
        viewModelScope.launch {
            try {
                api.call("\$events/result",obj("clientId" to identity,"eventId" to first.optString("eventId"),"outcome" to obj("kind" to "result","value" to value)))
                if (token==generation) pending=pending.filterNot { it===first }
            } catch(e: Exception) { if (token==generation) failure(e) }
            finally { if (token==generation) answering=false }
        }
    }
    fun loadMore() {
        val api=client ?: return; val id=selected?.id ?: return; val oldest=rows.minOfOrNull { it.seq } ?: return
        if (!hasMore || loadingHistory || historyCursor<0) return
        val token=generation; loadingHistory=true
        viewModelScope.launch {
            try {
                val result=api.call("session/page",obj("request" to obj("address" to obj("kind" to "session","sessionId" to id),"throughSeq" to historyCursor,"beforeSeq" to oldest,"maxMessages" to 30)))
                if (token!=generation) return@launch
                val records=result.objects("records").map(Events::event); rows=Events.merge(records.flatMap(Events::parse),rows)
                hasMore=result.optBoolean("hasMore") && records.any { it.optInt("seq")<oldest }
            } catch(e: Exception) { if (token==generation) failure(e) }
            finally { if (token==generation) loadingHistory=false }
        }
    }
    suspend fun attachment(image: ChatImage): ByteArray {
        val api=client ?: error("尚未连接"); val id=selected?.id ?: error("没有会话")
        val result=api.call("session/attachment",obj("request" to obj("sessionId" to id,"attachmentId" to image.id)))
        check(result.child("attachment").optString("attachmentId")==image.id) { "图片响应不匹配。" }
        val data=java.util.Base64.getDecoder().decode(result.getString("data")); check(data.size<=20*1024*1024) { "图片过大。" }; return data
    }
    // Debug-only fixture wiring; the release caller never enables loopback HTTP or imports a profile from an intent.
    fun useFixture() { if (BuildConfig.DEBUG) switchProfile(ConnectionProfile.create("http://127.0.0.1:38081","quick_tunnel",key="a".repeat(64),allowLocalTest=true)) }
    override fun onCleared() { stopSocket(); client?.close() }
}
