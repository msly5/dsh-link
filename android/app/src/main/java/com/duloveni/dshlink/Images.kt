package com.duloveni.dshlink

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

fun prepareImage(context: Context, uri: Uri): PendingImage {
    val bytes=context.contentResolver.openInputStream(uri)?.use { input ->
        val out=ByteArrayOutputStream(); val chunk=ByteArray(8192)
        while(true) {val n=input.read(chunk);if(n<0) break;out.write(chunk,0,n);require(out.size()<=25*1024*1024) {"图片文件过大，请选择小于 25 MB 的图片。"}}
        out.toByteArray()
    } ?: error("无法读取所选图片。")
    val bounds=BitmapFactory.Options().apply {inJustDecodeBounds=true}; BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
    require(bounds.outWidth>0 && bounds.outHeight>0 && bounds.outWidth.toLong()*bounds.outHeight<=100_000_000L) {"不支持此图片格式或尺寸。"}
    val options=BitmapFactory.Options().apply {inSampleSize=1;while(maxOf(bounds.outWidth,bounds.outHeight)/inSampleSize>2400) inSampleSize*=2}
    val bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.size,options) ?: error("图片解码失败。")
    val orientation=runCatching { ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL) }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
    val matrix=Matrix().apply {
        when(orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f,1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f,-1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {setRotate(90f);postScale(-1f,1f)}
            ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {setRotate(-90f);postScale(-1f,1f)}
            ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
        }
    }
    val oriented=if(matrix.isIdentity) bitmap else Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,matrix,true)
    val output=ByteArrayOutputStream(); oriented.compress(Bitmap.CompressFormat.JPEG,90,output)
    if(oriented!==bitmap) oriented.recycle();bitmap.recycle()
    require(output.size()<=5*1024*1024) {"图片压缩后仍然过大。"}
    return PendingImage(output.toByteArray(),"image.jpg")
}
