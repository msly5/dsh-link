package com.duloveni.dshlink

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

@Composable fun CommandSuggestions(model: LinkModel, query: String, select: (CommandDescriptor) -> Unit) {
    val matches=model.commands.filter { it.name.startsWith(query) }
    Column {
        Row(Modifier.fillMaxWidth().padding(start=8.dp),verticalAlignment=Alignment.CenterVertically) {
            Text("指令",Modifier.weight(1f),style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(model.loadingCommands) CircularProgressIndicator(Modifier.size(16.dp),strokeWidth=2.dp)
            IconButton(onClick={model.loadCommands()},enabled=!model.loadingCommands) {Icon(Icons.Outlined.Refresh,"刷新指令列表")}
        }
        LazyColumn(Modifier.fillMaxWidth().heightIn(max=150.dp)) {
            model.commandsError?.let { item {Text(it,Modifier.padding(8.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.error)} }
            if(matches.isEmpty()) item {Text(if(model.loadingCommands) "正在读取指令…" else if(model.commandsError!=null) "点右上角刷新重试" else "没有匹配的指令",Modifier.padding(8.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            items(matches,key={it.name}) {command ->
                Column(Modifier.fillMaxWidth().clickable {select(command)}.heightIn(min=48.dp).padding(horizontal=8.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(3.dp)) {
                    Text("/${command.name}",style=MaterialTheme.typography.bodyMedium,fontFamily=FontFamily.Monospace)
                    Text(command.description,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=2)
                }
            }
        }
        HorizontalDivider(Modifier.padding(top=6.dp))
    }
}
