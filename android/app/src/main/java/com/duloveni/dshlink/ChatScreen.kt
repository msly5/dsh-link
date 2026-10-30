package com.duloveni.dshlink

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

@Composable fun ChatScreen(model: LinkModel,modifier: Modifier) {
    val list=rememberLazyListState(); val scope=rememberCoroutineScope(); val context=LocalContext.current
    var controls by remember {mutableStateOf(false)}; var choosingImages by remember {mutableStateOf(false)}
    var composerFocused by remember {mutableStateOf(false)}
    val composerFocus=remember {FocusRequester()}
    val commandQuery=if(composerFocused && !model.sending) SlashCommands.suggestionQuery(model.draft) else null
    LaunchedEffect(commandQuery!=null) {if(commandQuery!=null && model.commands.isEmpty()) model.loadCommands()}
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris ->
        if(uris.isNotEmpty()) scope.launch {
            choosingImages=true
            val session=model.selected?.id
            try { val prepared=withContext(Dispatchers.IO) {uris.map {prepareImage(context,it)}}; if(model.selected?.id==session) model.images=(model.images+prepared).take(4) }
            catch(e: Exception) {model.error=e.message} finally {choosingImages=false}
        }
    }
    val timeline=remember(model.rows) {
        buildList<List<ChatRow>> {
            var tools=mutableListOf<ChatRow>()
            for(row in model.rows) {
                if(row.role=="tool") tools.add(row) else { if(tools.isNotEmpty()) {add(tools.toList());tools=mutableListOf()};add(listOf(row)) }
            }
            if(tools.isNotEmpty()) add(tools.toList())
        }
    }
    val nearBottom by remember {derivedStateOf {list.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let {it>=list.layoutInfo.totalItemsCount-3} ?: true}}
    LaunchedEffect(model.selected?.id) {if(timeline.isNotEmpty()) list.scrollToItem(timeline.size)}
    LaunchedEffect(model.rows.size,model.liveText.length,model.reasoning.length) {if(nearBottom && list.layoutInfo.totalItemsCount>0) list.scrollToItem(list.layoutInfo.totalItemsCount-1)}
    Column(modifier.fillMaxWidth().imePadding(),horizontalAlignment=Alignment.CenterHorizontally) {
        Box(Modifier.weight(1f).widthIn(max=800.dp).fillMaxWidth()) {
            LazyColumn(state=list,modifier=Modifier.fillMaxSize(),contentPadding=PaddingValues(22.dp,18.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
                item {if(model.hasMore) TextButton(enabled=!model.loadingHistory,onClick={model.loadMore()}) {Text(if(model.loadingHistory) "读取中…" else "加载更早的消息")}}
                items(timeline,key={it.first().id}) { group ->
                    if(group.first().role=="tool") ToolGroup(group) else Message(group.first(),model)
                }
                if(model.reasoning.isNotBlank()) item {ToolGroup(listOf(ChatRow("live-reasoning",0,"tool",model.reasoning,"思考中")))}
                if(model.liveText.isNotBlank()) item {Markdown(model.liveText)}
                if(model.running && model.liveText.isEmpty()) item {Row(verticalAlignment=Alignment.CenterVertically) {CircularProgressIndicator(Modifier.size(14.dp),strokeWidth=1.5.dp); Text("  正在执行…",fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
                item {Spacer(Modifier.height(12.dp))}
            }
            if(!nearBottom) SmallFloatingActionButton(onClick={scope.launch {list.animateScrollToItem((list.layoutInfo.totalItemsCount-1).coerceAtLeast(0))}},modifier=Modifier.align(Alignment.BottomEnd).padding(16.dp)) {Icon(Icons.Outlined.ArrowDownward,"回到最新消息")}
        }
        if(!model.connected) TextButton(onClick={model.reconnect()}) {Icon(Icons.Outlined.Refresh,null,Modifier.size(16.dp));Text(" 重新连接")}
        model.pending.firstOrNull()?.let { PendingCard(it,model) }
        Surface(Modifier.widthIn(max=800.dp).fillMaxWidth().padding(12.dp),shape=RoundedCornerShape(28.dp),color=MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.padding(10.dp)) {
                commandQuery?.let { query -> CommandSuggestions(model,query) {command -> model.draft="/${command.name} ";composerFocus.requestFocus()} }
                if(model.images.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    model.images.forEachIndexed {index,image ->
                        Box {
                            val bitmap=remember(image) {BitmapFactory.decodeByteArray(image.data,0,image.data.size)?.asImageBitmap()}
                            bitmap?.let {Image(it,"待发送图片",Modifier.size(72.dp))}
                            IconButton(onClick={model.images=model.images.filterIndexed {i,_->i!=index}},enabled=!model.sending,modifier=Modifier.size(28.dp).align(Alignment.TopEnd).background(MaterialTheme.colorScheme.surface,CircleShape)) {Icon(Icons.Outlined.Close,"移除图片",Modifier.size(16.dp))}
                        }
                    }
                }
                TextField(model.draft,{model.draft=it},enabled=!model.sending,placeholder={Text("告诉 DSH 下一步做什么…")},modifier=Modifier.fillMaxWidth().focusRequester(composerFocus).onFocusChanged {composerFocused=it.isFocused}.heightIn(min=56.dp,max=180.dp),colors=TextFieldDefaults.colors(focusedContainerColor=MaterialTheme.colorScheme.surfaceContainer,unfocusedContainerColor=MaterialTheme.colorScheme.surfaceContainer,disabledContainerColor=MaterialTheme.colorScheme.surfaceContainer,focusedIndicatorColor=androidx.compose.ui.graphics.Color.Transparent,unfocusedIndicatorColor=androidx.compose.ui.graphics.Color.Transparent,disabledIndicatorColor=androidx.compose.ui.graphics.Color.Transparent))
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                    IconButton(enabled=!model.sending && !choosingImages && model.images.size<4,onClick={picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))}) {Icon(Icons.Outlined.AddPhotoAlternate,"添加图片")}
                    TextButton(onClick={controls=true},modifier=Modifier.weight(1f)) {
                        val selection=model.values.child("modelSelection").let {it.optJSONObject("next") ?: it.child("lastUsed")}
                        Text(selection.optString("model").ifBlank {"模型与权限"},maxLines=1,overflow=TextOverflow.Ellipsis,fontSize=12.sp);Icon(Icons.Outlined.ExpandMore,null,Modifier.size(16.dp))
                    }
                    if(choosingImages || model.sending) CircularProgressIndicator(Modifier.size(24.dp),strokeWidth=2.dp)
                    else if(model.running) FilledIconButton(onClick={model.cancel()}) {Icon(Icons.Outlined.Stop,"停止任务")}
                    else FilledIconButton(onClick={model.send()},enabled=model.connected && (model.draft.isNotBlank() || model.images.isNotEmpty())) {Icon(Icons.Outlined.ArrowUpward,"发送消息")}
                }
            }
        }
    }
    if(controls) SessionControls(model) {controls=false}
}
@Composable private fun Message(row: ChatRow,model: LinkModel) {
    Column(Modifier.fillMaxWidth(),horizontalAlignment=if(row.role=="user") Alignment.End else Alignment.Start,verticalArrangement=Arrangement.spacedBy(8.dp)) {
        if(row.role=="user") Surface(shape=RoundedCornerShape(20.dp),color=MaterialTheme.colorScheme.surfaceContainerHighest) {Text(row.text,Modifier.padding(16.dp),lineHeight=25.sp)}
        else {Row(verticalAlignment=Alignment.CenterVertically) {Whale(Modifier.size(24.dp));Text("DSH",Modifier.padding(start=8.dp),style=MaterialTheme.typography.labelLarge)};Markdown(row.text)}
        row.images.forEach {image -> Attachment(image,model)}
    }
}
@Composable private fun Attachment(image: ChatImage,model: LinkModel) {
    var bitmap by remember(image.id) {mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null)}; var error by remember {mutableStateOf<String?>(null)};var loading by remember {mutableStateOf(false)}
    val scope=rememberCoroutineScope()
    bitmap?.let {Image(it,image.name,Modifier.fillMaxWidth().heightIn(max=320.dp))} ?: OutlinedButton(enabled=!loading,onClick={scope.launch {loading=true;try {val bytes=model.attachment(image);bitmap=withContext(Dispatchers.Default) {BitmapFactory.decodeByteArray(bytes,0,bytes.size)?.asImageBitmap()};if(bitmap==null) error="无法显示图片"} catch(e: Exception) {error=e.message} finally {loading=false}}}) {Icon(Icons.Outlined.Image,null);Text(if(loading) " 加载图片…" else " 查看图片")}
    error?.let {Text(it,color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)}
}
@Composable private fun ToolGroup(rows: List<ChatRow>) {
    var expanded by remember(rows.first().id) {mutableStateOf(false)}
    Column {
        Row(Modifier.fillMaxWidth().clickable {expanded=!expanded}.padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
            Icon(if(expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ChevronRight,null,Modifier.size(18.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
            Text(if(rows.size==1) rows.first().label.ifBlank {"执行结果"} else "执行过程 · ${rows.size} 项",fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(start=8.dp))
        }
        if(expanded) rows.forEach {row ->
            var open by remember(row.id) {mutableStateOf(false)}
            Row(Modifier.fillMaxWidth().clickable {open=!open}.padding(vertical=8.dp,horizontal=10.dp),verticalAlignment=Alignment.CenterVertically) {
                Icon(Icons.Outlined.Terminal,null,Modifier.size(17.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
                Text(row.label.ifBlank {"执行结果"}+" · "+row.text.replace('\n',' ').take(160),modifier=Modifier.weight(1f).padding(start=8.dp),fontSize=13.sp,maxLines=1,overflow=TextOverflow.Ellipsis,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if(open) Surface(color=MaterialTheme.colorScheme.surfaceContainer,shape=RoundedCornerShape(12.dp)) {Column(Modifier.fillMaxWidth().padding(12.dp)) {if(row.detail.isNotBlank()) Text(row.detail,fontSize=12.sp);Markdown(row.text)}}
        }
    }
}
@Composable private fun PendingCard(frame: JSONObject,model: LinkModel) {
    val request=frame.child("request");val approval=frame.optString("event")=="approval/request"
    val answers=remember(frame.optString("eventId")) {mutableStateMapOf<String,String>()}
    val selected=remember(frame.optString("eventId")) {mutableStateMapOf<String,List<String>>()}
    Surface(Modifier.widthIn(max=800.dp).fillMaxWidth().padding(horizontal=12.dp),color=MaterialTheme.colorScheme.surfaceContainerHighest,shape=RoundedCornerShape(18.dp)) {
        Column(Modifier.heightIn(max=300.dp).verticalScroll(rememberScrollState()).padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(if(approval) "需要你的确认" else "需要你的回答",style=MaterialTheme.typography.titleMedium)
            if(approval) {
                Text(request.optString("toolName","工具调用")+"\n"+request.optString("reason"),fontSize=14.sp)
                Row {OutlinedButton(enabled=model.connected && !model.answering,onClick={model.answer("rejected")}) {Text("拒绝")};Spacer(Modifier.width(12.dp));Button(enabled=model.connected && !model.answering,onClick={model.answer("allowed-once")}) {Text("允许一次")}}
            } else {
                val questions=request.objects("questions")
                questions.forEach {q -> val id=q.optString("id")
                    Text(q.optString("question"),fontSize=14.sp)
                    val options=q.objects("options").map {it.optString("label")}
                    if(options.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)) {options.forEach {option -> FilterChip(selected[id].orEmpty().contains(option),onClick={
                        val old=selected[id].orEmpty()
                        selected[id]=if(q.optBoolean("multiSelect")) {if(option in old) old-option else old+option} else {answers[id]="";if(option in old) emptyList() else listOf(option)}
                    },label={Text(option)})}}
                    OutlinedTextField(answers[id].orEmpty(),{answers[id]=it;if(!q.optBoolean("multiSelect") && it.isNotBlank()) selected[id]=emptyList()},label={Text("回答")},modifier=Modifier.fillMaxWidth())
                }
                Button(enabled=model.connected && !model.answering && questions.all {!answers[it.optString("id")].isNullOrBlank() || !selected[it.optString("id")].isNullOrEmpty()},onClick={model.answer(obj("answers" to JSONArray(questions.map {q->obj("id" to q.optString("id"),"selected" to JSONArray(selected[q.optString("id")].orEmpty()),"custom" to answers[q.optString("id")].orEmpty())})))}) {Text("提交回答")}
            }
        }
    }
}
@Composable private fun SessionControls(model: LinkModel,close:()->Unit) {
    AlertDialog(onDismissRequest=close,title={Text("模型与权限")},text={LazyColumn {
        model.catalog.objects("groups").forEach {provider ->
            item {Text(provider.optString("name"),style=MaterialTheme.typography.labelLarge,modifier=Modifier.padding(vertical=10.dp))}
            items(provider.objects("models")) {entry ->
                Column {
                    TextButton(onClick={model.chooseModel(provider.optString("id"),entry.optString("id"),null);close()}) {Text(entry.optString("name",entry.optString("id")))}
                    val efforts=entry.child("reasoning").objects("efforts")
                    if(efforts.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState())) {efforts.forEach {effort -> TextButton(onClick={model.chooseModel(provider.optString("id"),entry.optString("id"),effort.optString("id"));close()}) {Text(effort.optString("name",effort.optString("id")),fontSize=12.sp)}}}
                }
            }
        }
        item {HorizontalDivider(Modifier.padding(vertical=12.dp));Text("会话权限",style=MaterialTheme.typography.labelLarge)}
        items(model.permissions) {permission -> TextButton(onClick={model.permission(permission.optString("value"));close()}) {Text(permission.optString("name",permission.optString("value")))}}
        if(model.catalog.objects("groups").isEmpty() && model.permissions.isEmpty()) item {Text("目录尚未加载，请连接后重试。")}
    }},confirmButton={TextButton(onClick=close) {Text("完成")}})
}
