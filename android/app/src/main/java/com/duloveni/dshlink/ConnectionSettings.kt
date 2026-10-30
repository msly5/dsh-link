package com.duloveni.dshlink

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.launch

@Composable fun ConnectionSettings(model: LinkModel,imported: ConnectionProfile?,close:()->Unit) {
    val initial=imported ?: model.profile
    var server by remember { mutableStateOf(initial?.server.orEmpty()) }; var mode by remember { mutableStateOf(initial?.mode ?: "access") }
    var id by remember { mutableStateOf(initial?.clientId.orEmpty()) }; var secret by remember { mutableStateOf(initial?.secret.orEmpty()) }; var key by remember { mutableStateOf(initial?.connectionKey.orEmpty()) }
    var error by remember { mutableStateOf<String?>(null) }; var status by remember { mutableStateOf<String?>(null) }; var testing by remember { mutableStateOf(false) }
    var showing by remember { mutableStateOf(false) }; var clearing by remember { mutableStateOf(false) }
    val scope=rememberCoroutineScope()
    fun import(profile: ConnectionProfile) { server=profile.server; mode=profile.mode; id=profile.clientId; secret=profile.secret; key=profile.connectionKey; error=null; status="已读取二维码。请确认服务器地址，测试后保存。" }
    LaunchedEffect(imported) { imported?.let(::import) }
    val scanner=rememberLauncherForActivityResult(ScanContract()) { result ->
        result.contents?.let { raw -> try { import(ConnectionProfile.invitation(raw)) } catch(e: Exception) {error=e.message} }
    }
    fun profile() = ConnectionProfile.create(server,mode,id,secret,key)
    Dialog(onDismissRequest=close,properties=DialogProperties(usePlatformDefaultWidth=false)) {
        Surface(Modifier.fillMaxWidth().fillMaxHeight(0.97f),shape=MaterialTheme.shapes.extraLarge) {
            Column(Modifier.safeDrawingPadding().imePadding()) {
                Row(Modifier.fillMaxWidth().padding(12.dp),horizontalArrangement=Arrangement.SpaceBetween) {
                    TextButton(onClick=close) {Text("取消")}; Text("设置",style=MaterialTheme.typography.titleMedium,modifier=Modifier.padding(top=12.dp))
                    TextButton(enabled=!testing,onClick={try {model.saveProfile(profile()); if(model.error==null) close() else error=model.error} catch(e: Exception) {error=e.message}}) {Text("保存")}
                }
                Column(Modifier.weight(1f).widthIn(max=600.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
                    AppearanceSection()
                    HorizontalDivider()
                    Text("连接你的电脑",style=MaterialTheme.typography.headlineMedium,fontFamily=FontFamily.Serif)
                    Text("连接 Mac 或 Windows 上的 DSH。凭证通过 Android Keystore 加密保存，仅用于你填写的服务器。",color=MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(enabled=!testing,onClick={scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt("扫描电脑上的 dsh link 连接二维码").setBeepEnabled(false).setOrientationLocked(false))},modifier=Modifier.fillMaxWidth(),contentPadding=PaddingValues(16.dp)) { Icon(Icons.Outlined.QrCodeScanner,null); Spacer(Modifier.width(10.dp)); Text("扫描连接二维码") }
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf("access" to "Access（推荐）","quick_tunnel" to "Quick Tunnel").forEachIndexed { index,pair ->
                            SegmentedButton(mode==pair.first,onClick={mode=pair.first;status=null;error=null},shape=SegmentedButtonDefaults.itemShape(index,2),enabled=!testing) {Text(pair.second)}
                        }
                    }
                    OutlinedTextField(server,{new-> if(new.trimEnd('/')!=server.trimEnd('/')) {id="";secret="";key=""};server=new;status=null},label={Text("服务器地址")},placeholder={Text("https://dsh.example.com")},singleLine=true,enabled=!testing,modifier=Modifier.fillMaxWidth())
                    if(mode=="access") {
                        OutlinedTextField(id,{id=it;status=null},label={Text("Client ID")},singleLine=true,enabled=!testing,modifier=Modifier.fillMaxWidth())
                        OutlinedTextField(secret,{secret=it;status=null},label={Text("Client Secret")},singleLine=true,enabled=!testing,modifier=Modifier.fillMaxWidth(),visualTransformation=if(showing) VisualTransformation.None else PasswordVisualTransformation())
                        Text("使用 Cloudflare Access Service Token；不是 API Token，也不是 Tunnel Token。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        OutlinedTextField(key,{key=it;status=null},label={Text("连接密钥")},singleLine=true,enabled=!testing,modifier=Modifier.fillMaxWidth(),visualTransformation=if(showing) VisualTransformation.None else PasswordVisualTransformation())
                        Text("运行电脑端 Quick Tunnel 后扫码或手动填写。临时地址和密钥会在重启后变化，需要重新配置。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    TextButton(onClick={showing=!showing}) {Icon(if(showing) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,null);Spacer(Modifier.width(8.dp));Text(if(showing) "隐藏密钥" else "显示密钥")}
                    error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
                    status?.let {Text(it,color=MaterialTheme.colorScheme.primary)}
                    Button(enabled=!testing,onClick={
                        try {
                            val connection=profile(); testing=true;error=null;status=null
                            scope.launch {
                                val api=RemoteClient(connection)
                                try { api.sessions();api.workspace();status="连接成功：会话接口和消息流均可用。" }
                                catch(e: Exception) {error=e.message ?: "连接失败。"}
                                finally {api.close();testing=false}
                            }
                        } catch(e: Exception) {error=e.message}
                    },modifier=Modifier.fillMaxWidth(),contentPadding=PaddingValues(16.dp)) {if(testing) {CircularProgressIndicator(Modifier.size(18.dp),strokeWidth=2.dp);Spacer(Modifier.width(10.dp))};Text(if(testing) "正在测试…" else "测试连接")}
                    Text("测试不会保存凭证。点“保存”后应用。修改服务器地址会清除原地址的凭证。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    TextButton(onClick={clearing=true}) {Text("清除已保存的连接",color=MaterialTheme.colorScheme.error)}
                    Text("dsh link · 非官方 DSH 远程客户端\nAndroid 首版暂不支持系统推送通知。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
    if(clearing) AlertDialog(onDismissRequest={clearing=false},title={Text("清除连接？")},text={Text("将清除本机保存的凭证和当前内存中的会话，不影响电脑上的数据。")},confirmButton={TextButton(onClick={model.clearProfile();close()}) {Text("清除")}},dismissButton={TextButton(onClick={clearing=false}) {Text("取消")}})
}
