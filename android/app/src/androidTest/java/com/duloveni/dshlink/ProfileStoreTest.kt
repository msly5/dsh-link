package com.duloveni.dshlink
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
@RunWith(AndroidJUnit4::class)
class ProfileStoreTest {
    @Test fun profileIsEncryptedAndCanBeCleared() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val store=ProfileStore(context)
        try {
            store.save(ConnectionProfile.create("https://fixture.example.com","access","test-id","test-private-secret"))
            assertEquals("test-private-secret",store.load()?.secret)
            val raw=context.getSharedPreferences("secure_connection",0).getString("encrypted","")!!
            assertFalse(raw.contains("test-private-secret")); assertFalse(raw.contains("fixture.example.com"))
            store.clear();assertNull(store.load())
        } finally {store.clear()}
    }
}
