package id.kaffepos.kasir

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/** Printer thermal Bluetooth Classic (SPP) untuk channel "kaffepos/printer" (desain §13). */
@SuppressLint("MissingPermission") // izin BLUETOOTH_CONNECT dicek di awal setiap panggilan
class MainActivity : FlutterActivity() {
    private val spp: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val io = Executors.newSingleThreadExecutor()
    private var socket: BluetoothSocket? = null
    private var socketAddress: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaffepos/printer").setMethodCallHandler { call, result ->
            if (Build.VERSION.SDK_INT >= 31 &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 1)
                result.error("permission", "Izin Bluetooth belum diberikan", null)
                return@setMethodCallHandler
            }
            val adapter = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter
            if (adapter == null || !adapter.isEnabled) {
                result.error("io", "Bluetooth mati", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "paired" -> result.success(adapter.bondedDevices.map {
                    mapOf("name" to (it.name ?: it.address), "address" to it.address)
                })
                "print" -> {
                    val address = call.argument<String>("address")!!
                    val bytes = call.argument<ByteArray>("bytes")!!
                    io.execute {
                        val error = try {
                            write(adapter, address, bytes)
                            null
                        } catch (e: IOException) {
                            e.message ?: "gagal mengirim"
                        }
                        runOnUiThread {
                            if (error == null) result.success(true) else result.error("io", error, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Pakai ulang koneksi; jika putus, sambung ulang sekali lalu kirim lagi (PRD K-13: auto-reconnect). */
    private fun write(adapter: BluetoothAdapter, address: String, bytes: ByteArray) {
        for (attempt in 1..2) {
            try {
                val s = socket?.takeIf { socketAddress == address && it.isConnected } ?: connect(adapter, address)
                s.outputStream.write(bytes)
                s.outputStream.flush()
                return
            } catch (e: IOException) {
                closeSocket()
                if (attempt == 2) throw e
            }
        }
    }

    private fun connect(adapter: BluetoothAdapter, address: String): BluetoothSocket {
        closeSocket()
        val device = adapter.getRemoteDevice(address)
        val secure = device.createRfcommSocketToServiceRecord(spp)
        val s = try {
            secure.connect()
            secure
        } catch (e: IOException) {
            try {
                secure.close()
            } catch (ignored: IOException) {
            }
            // Sebagian printer murah hanya menerima koneksi insecure.
            device.createInsecureRfcommSocketToServiceRecord(spp).also { it.connect() }
        }
        socket = s
        socketAddress = address
        return s
    }

    private fun closeSocket() {
        try {
            socket?.close()
        } catch (ignored: IOException) {
        }
        socket = null
        socketAddress = null
    }

    override fun onDestroy() {
        closeSocket()
        io.shutdown()
        super.onDestroy()
    }
}
