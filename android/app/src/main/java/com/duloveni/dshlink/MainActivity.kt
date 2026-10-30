package com.duloveni.dshlink

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.core.view.WindowCompat
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private var invitation by mutableStateOf<String?>(null)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        invitation=intent.dataString
        setContent {
            val appearance = remember { AppearancePreferences(applicationContext) }
            val dark = when (appearance.mode) {
                AppearanceMode.SYSTEM -> isSystemInDarkTheme()
                AppearanceMode.LIGHT -> false
                AppearanceMode.DARK -> true
            }
            SideEffect {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            CompositionLocalProvider(LocalAppearance provides appearance) {
            LinkTheme(dark) {
                val model: LinkModel=viewModel()
                LaunchedEffect(Unit) { if (BuildConfig.DEBUG && intent.getBooleanExtra("fixture",false)) model.useFixture() }
                LinkApp(model, invitation) { invitation=null }
            }
            }
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); invitation=intent.dataString }
}
@Composable fun LinkTheme(dark: Boolean, content: @Composable () -> Unit) {
    val colors=if(dark) darkColorScheme(primary=Color(0xFFE6E5DF),onPrimary=Color(0xFF20211E),background=Color(0xFF181917),surface=Color(0xFF181917),onSurface=Color(0xFFE8E7E1),onSurfaceVariant=Color(0xFFABAFA5),surfaceContainer=Color(0xFF232420),surfaceContainerHighest=Color(0xFF2D2F29),outlineVariant=Color(0xFF3B3D35))
    else lightColorScheme(primary=Color(0xFF252622),onPrimary=Color(0xFFFAFAF7),background=Color(0xFFFAFAF7),surface=Color(0xFFFAFAF7),onSurface=Color(0xFF252622),onSurfaceVariant=Color(0xFF797C72),surfaceContainer=Color(0xFFF0F0EB),surfaceContainerHighest=Color(0xFFE7E8E1),outlineVariant=Color(0xFFDDDFD5))
    MaterialTheme(colorScheme=colors,content=content)
}
@Composable fun Whale(modifier: Modifier=Modifier) { Image(painterResource(R.drawable.whale),contentDescription="dsh link",modifier=modifier.then(Modifier.clip(RoundedCornerShape(16.dp)))) }

@Composable private fun LinkApp(model: LinkModel, invitation: String?, consumed: ()->Unit) {
    var settings by remember { mutableStateOf(false) }; var drawer by remember { mutableStateOf(false) }; var creating by remember { mutableStateOf(false) }
    var imported by remember { mutableStateOf<ConnectionProfile?>(null) }
    var archiving by remember { mutableStateOf<Session?>(null) }
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer=LifecycleEventObserver { _,event -> when(event) { Lifecycle.Event.ON_START -> model.setActive(true); Lifecycle.Event.ON_STOP -> model.setActive(false); else -> Unit } }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(model.profile) { while(true) { delay(30000); if(lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) model.refresh() } }
    LaunchedEffect(invitation) {
        if (invitation!=null) {
            try { imported=ConnectionProfile.invitation(invitation); settings=true } catch(e: Exception) { model.error=e.message }
            consumed()
        }
    }
    BackHandler(drawer || model.selected!=null) { if(drawer) drawer=false else model.select(null) }
    Surface(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val wide=maxWidth>=840.dp
            Row(Modifier.fillMaxSize()) {
                if(wide) Sidebar(model,Modifier.width(300.dp).fillMaxHeight(), {settings=true}, {creating=true}, {model.select(it)}, {archiving=it})
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal=12.dp),verticalAlignment=Alignment.CenterVertically) {
                        if(!wide) IconButton(onClick={drawer=true}) { Icon(Icons.Outlined.Menu,"会话侧栏") }
                        Column(Modifier.weight(1f).padding(horizontal=8.dp)) {
                            Text(model.selected?.title ?: "dsh link",maxLines=1,overflow=TextOverflow.Ellipsis,fontFamily=if(model.selected==null) FontFamily.Serif else FontFamily.Default,fontWeight=FontWeight.SemiBold,fontSize=22.sp)
                            if(model.selected!=null) Text(if(model.connected) (if(model.running) "正在执行" else "已连接") else "正在连接…",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton(onClick={if(model.profile==null) settings=true else creating=true}) { Icon(Icons.Outlined.Edit,"新建对话") }
                    }
                    model.error?.let { message -> Surface(color=MaterialTheme.colorScheme.errorContainer) { Row(Modifier.padding(horizontal=16.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically) {
                        Text(message,Modifier.weight(1f),fontSize=13.sp,color=MaterialTheme.colorScheme.onErrorContainer)
                        IconButton(onClick={model.error=null}) { Icon(Icons.Outlined.Close,"关闭提示") }
                    } } }
                    if(model.selected==null) {
                        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(28.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                            Whale(Modifier.size(68.dp)); Spacer(Modifier.height(28.dp))
                            Text("从这里，继续。",fontSize=32.sp,fontFamily=FontFamily.Serif)
                            Text("连上你的电脑，接着上次的思路。",color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(top=16.dp,bottom=30.dp))
                            Button(onClick={if(model.profile==null) settings=true else creating=true},contentPadding=PaddingValues(24.dp,15.dp)) { Icon(Icons.Outlined.Add,null); Spacer(Modifier.width(8.dp)); Text(if(model.profile==null) "连接电脑" else "新建对话") }
                        }
                        TextButton(onClick={settings=true},modifier=Modifier.align(Alignment.CenterHorizontally).padding(bottom=26.dp)) { Icon(Icons.Outlined.Link,null,Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("设置") }
                    } else ChatScreen(model,Modifier.weight(1f))
                }
            }
            if(drawer && !wide) {
                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha=0.25f)).clickable {drawer=false})
                Sidebar(model,Modifier.widthIn(max=340.dp).fillMaxWidth(0.85f).fillMaxHeight(),{drawer=false;settings=true},{drawer=false;creating=true},{drawer=false;model.select(it)},{archiving=it})
            }
        }
    }
    if(settings) ConnectionSettings(model,imported,{imported=null;settings=false})
    if(creating) AlertDialog(onDismissRequest={creating=false},title={Text("选择桌面工作区")},text={
        LazyColumn {
            if(model.workspaces.isEmpty()) item { Text(if(model.busy) "正在读取工作区…" else "暂无工作区。请先在桌面端打开工作区，再刷新。") }
            items(model.workspaces,key={it.id}) { workspace -> ListItem(headlineContent={Text(workspace.title)},supportingContent={Text(workspace.path,maxLines=2,overflow=TextOverflow.Ellipsis)},leadingContent={Icon(Icons.Outlined.Folder,null)},modifier=Modifier.clickable {creating=false;model.create(workspace)}) }
        }
    },confirmButton={TextButton(onClick={model.refresh()}) {Text("刷新")}},dismissButton={TextButton(onClick={creating=false}) {Text("取消")}})
    archiving?.let { session ->
        val restore=session.id in model.archived
        AlertDialog(onDismissRequest={archiving=null},title={Text(if(restore) "恢复会话" else "归档会话")},text={Text(if(!restore && session.running) "“${session.title}”正在执行。归档会停止当前任务，并同步到桌面端。" else "${if(restore) "恢复" else "归档"}“${session.title}”？状态会同步到桌面端。")},confirmButton={TextButton(onClick={archiving=null;model.archive(session,!restore)}) {Text(if(restore) "恢复" else "归档")}},dismissButton={TextButton(onClick={archiving=null}) {Text("取消")}})
    }
}
@Composable private fun Sidebar(model: LinkModel,modifier: Modifier,settings:()->Unit,create:()->Unit,select:(Session)->Unit,archive:(Session)->Unit) {
    var filter by remember { mutableStateOf("") }; var showArchived by remember { mutableStateOf(false) }; val collapsed=remember { mutableStateMapOf<String,Boolean>() }
    val visible=model.sessions.filter { (it.id in model.archived)==showArchived && (filter.isBlank() || it.title.contains(filter,true) || it.cwd.contains(filter,true)) }
    Surface(modifier,color=MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.padding(horizontal=16.dp)) {
            Row(Modifier.fillMaxWidth().padding(top=20.dp,bottom=18.dp),verticalAlignment=Alignment.CenterVertically) { Whale(Modifier.size(32.dp)); Text("dsh link",fontSize=27.sp,fontFamily=FontFamily.Serif,modifier=Modifier.weight(1f).padding(start=10.dp)); IconButton(onClick=settings) {Icon(Icons.Outlined.Settings,"设置")} }
            OutlinedTextField(filter,{filter=it},placeholder={Text("搜索会话")},leadingIcon={Icon(Icons.Outlined.Search,null)},singleLine=true,modifier=Modifier.fillMaxWidth(),shape=RoundedCornerShape(28.dp))
            Row(Modifier.padding(vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                FilterChip(!showArchived,{showArchived=false},label={Text("对话")})
                FilterChip(showArchived,{showArchived=true},label={Text("已归档")})
                IconButton(onClick={model.refresh()}) {Icon(Icons.Outlined.Refresh,"刷新会话")}
            }
            LazyColumn(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
                if(model.busy && visible.isEmpty()) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                if(visible.isEmpty()) item {Text(if(model.profile==null) "连接电脑后，会话将显示在这里。" else "没有匹配的会话",color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(16.dp))}
                val grouped=model.workspaces.map { it to visible.filter { s -> s.id in it.sessions } }.filter { it.second.isNotEmpty() }
                grouped.forEach { (workspace, items) ->
                    item(key="workspace:${workspace.id}") { Row(Modifier.fillMaxWidth().clickable {collapsed[workspace.id]=collapsed[workspace.id]!=true}.padding(vertical=12.dp),verticalAlignment=Alignment.CenterVertically) {
                        Icon(if(collapsed[workspace.id]==true) Icons.Outlined.ChevronRight else Icons.Outlined.ExpandMore,null,Modifier.size(18.dp)); Text(workspace.title,style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(start=5.dp))
                    } }
                    if(collapsed[workspace.id]!=true) items(items,key={it.id}) { s -> SessionRow(s,s.id==model.selected?.id,select,archive) }
                }
                val assigned=grouped.flatMap { it.second }.map { it.id }.toSet()
                items(visible.filterNot { it.id in assigned },key={it.id}) { s -> SessionRow(s,s.id==model.selected?.id,select,archive) }
            }
            Button(onClick={if(model.profile==null) settings() else create()},modifier=Modifier.fillMaxWidth().padding(vertical=16.dp),contentPadding=PaddingValues(16.dp)) { Icon(Icons.Outlined.Add,null); Spacer(Modifier.width(8.dp)); Text("新建对话") }
        }
    }
}
@Composable private fun SessionRow(s: Session,selected: Boolean,select:(Session)->Unit,archive:(Session)->Unit) {
    Surface(shape=RoundedCornerShape(14.dp),color=if(selected) MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent) {
        Row(Modifier.fillMaxWidth().clickable {select(s)}.padding(start=12.dp),verticalAlignment=Alignment.CenterVertically) {
            Icon(if(s.running) Icons.Outlined.Autorenew else Icons.Outlined.ChatBubbleOutline,null,Modifier.size(19.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
            Text(s.title,Modifier.weight(1f).padding(12.dp,14.dp),maxLines=2,overflow=TextOverflow.Ellipsis,fontSize=15.sp)
            IconButton(onClick={archive(s)},modifier=Modifier.size(36.dp)) {Icon(Icons.Outlined.Inventory2,"归档或恢复会话",Modifier.size(17.dp))}
        }
    }
}
