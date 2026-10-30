package com.duloveni.dshlink

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

enum class AppearanceMode(val title: String) { SYSTEM("跟随系统"), LIGHT("浅色"), DARK("深色") }

class AppearancePreferences(context: Context) {
    private val preferences = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
    var mode by mutableStateOf(AppearanceMode.entries.firstOrNull { it.name == preferences.getString("mode", null) } ?: AppearanceMode.SYSTEM)
        private set
    fun select(value: AppearanceMode) {
        mode = value
        preferences.edit().putString("mode", value.name).apply()
    }
}

val LocalAppearance = staticCompositionLocalOf<AppearancePreferences> { error("Missing appearance preferences") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun AppearanceSection() {
    val appearance = LocalAppearance.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("外观", style = MaterialTheme.typography.titleMedium)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            AppearanceMode.entries.forEachIndexed { index, mode ->
                SegmentedButton(selected = appearance.mode == mode, onClick = { appearance.select(mode) },
                    shape = SegmentedButtonDefaults.itemShape(index, AppearanceMode.entries.size)) { Text(mode.title) }
            }
        }
        Text("立即生效，自动保存。默认跟随系统。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
