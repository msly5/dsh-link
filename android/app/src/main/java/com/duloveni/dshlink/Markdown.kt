package com.duloveni.dshlink

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.commonmark.node.*
import org.commonmark.parser.Parser
import org.commonmark.ext.gfm.tables.*

private val markdownParser = Parser.builder().extensions(listOf(TablesExtension.create())).build()
private fun Node.children(): List<Node> = buildList { var c=firstChild; while(c!=null) { add(c); c=c.next } }
private fun plain(node: Node): String = when(node) { is Text -> node.literal; is Code -> node.literal; is SoftLineBreak,is HardLineBreak -> "\n"; else -> node.children().joinToString("") { plain(it) } }

@Composable fun Markdown(text: String, modifier: Modifier = Modifier) {
    val document = remember(text) { markdownParser.parse(text) }
    Column(modifier, verticalArrangement=Arrangement.spacedBy(10.dp)) { document.children().forEach { Block(it) } }
}
@Composable private fun Block(node: Node) {
    when(node) {
        is org.commonmark.node.Paragraph -> Inline(node)
        is Heading -> Inline(node, MaterialTheme.typography.titleLarge.copy(fontSize=(26-node.level*2).sp,fontWeight=FontWeight.SemiBold))
        is BulletList, is OrderedList -> Column(verticalArrangement=Arrangement.spacedBy(7.dp)) {
            node.children().forEachIndexed { i,item -> Row {
                androidx.compose.material3.Text(if(node is OrderedList) "${node.markerStartNumber+i}. " else "• ",modifier=Modifier.width(28.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(5.dp)) { item.children().forEach { Block(it) } }
            } }
        }
        is BlockQuote -> Row { Box(Modifier.width(3.dp).height(36.dp).background(MaterialTheme.colorScheme.outlineVariant)); Column(Modifier.padding(start=12.dp)) { node.children().forEach { Block(it) } } }
        is FencedCodeBlock -> CodeBlock(node.literal)
        is IndentedCodeBlock -> CodeBlock(node.literal)
        is ThematicBreak -> HorizontalDivider()
        is TableBlock -> Table(node)
        is HtmlBlock -> SelectionContainer { androidx.compose.material3.Text(node.literal) }
        else -> node.children().forEach { Block(it) }
    }
}
@Composable private fun CodeBlock(text: String) {
    Surface(shape=MaterialTheme.shapes.medium,color=MaterialTheme.colorScheme.surfaceContainer) {
        SelectionContainer { androidx.compose.material3.Text(text.trimEnd(),fontFamily=FontFamily.Monospace,fontSize=13.sp,
            modifier=Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(14.dp)) }
    }
}
@Composable private fun Table(table: TableBlock) {
    val rows=table.children().flatMap { it.children() }
    Column {
        androidx.compose.material3.Text("↔ 左右滑动查看完整表格",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top=6.dp).border(1.dp,MaterialTheme.colorScheme.outlineVariant)) {
            rows.forEachIndexed { i,row ->
                Row(Modifier.height(IntrinsicSize.Min).background(if(i==0) MaterialTheme.colorScheme.surfaceContainer else Color.Transparent)) {
                    row.children().forEach { cell ->
                        Box(Modifier.width(170.dp).fillMaxHeight().border(0.5.dp,MaterialTheme.colorScheme.outlineVariant).padding(10.dp)) {
                            Inline(cell,MaterialTheme.typography.bodyMedium.copy(fontWeight=if(i==0) FontWeight.SemiBold else FontWeight.Normal))
                        }
                    }
                }
            }
        }
    }
}
@Composable private fun Inline(node: Node, style: TextStyle = MaterialTheme.typography.bodyLarge) {
    val linkColor=MaterialTheme.colorScheme.primary; val codeColor=MaterialTheme.colorScheme.surfaceContainerHighest
    val text=remember(node,linkColor,codeColor) {
        buildAnnotatedString {
            fun appendNode(n: Node) {
                when(n) {
                    is Text -> append(n.literal)
                    is Code -> withStyle(SpanStyle(fontFamily=FontFamily.Monospace,background=codeColor)) { append(n.literal) }
                    is StrongEmphasis -> withStyle(SpanStyle(fontWeight=FontWeight.Bold)) { n.children().forEach(::appendNode) }
                    is Emphasis -> withStyle(SpanStyle(fontStyle=androidx.compose.ui.text.font.FontStyle.Italic)) { n.children().forEach(::appendNode) }
                    is Link -> { pushStringAnnotation("URL",n.destination); withStyle(SpanStyle(color=linkColor,textDecoration=androidx.compose.ui.text.style.TextDecoration.Underline)) { n.children().forEach(::appendNode) }; pop() }
                    is Image -> append("[图片：${plain(n)}]") // Remote images never load automatically.
                    is SoftLineBreak, is HardLineBreak -> append("\n")
                    is HtmlInline -> append(n.literal)
                    else -> n.children().forEach(::appendNode)
                }
            }
            node.children().forEach(::appendNode)
        }
    }
    val handler=LocalUriHandler.current
    SelectionContainer {
        ClickableText(text=text, style=style.copy(color=MaterialTheme.colorScheme.onSurface,lineHeight=style.fontSize*1.5), onClick={ position ->
            text.getStringAnnotations("URL",position,position).firstOrNull()?.item?.let { url ->
                if(url.startsWith("https://") || url.startsWith("http://")) runCatching { handler.openUri(url) }
            }
        })
    }
}
