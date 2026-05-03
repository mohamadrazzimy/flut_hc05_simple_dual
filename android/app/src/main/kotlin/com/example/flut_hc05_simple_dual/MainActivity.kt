package com.example.flut_hc05_simple_dual

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    private val channelName = "classic_bluetooth"
    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

    private var socket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null

    private val sppUuid: UUID =
        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "getPairedDevices" -> {
                    result.success(getPairedDevices())
                }

                "connect" -> {
                    val address = call.argument<String>("address")

                    if (address == null) {
                        result.success(
                            mapOf(
                                "success" to false,
                                "message" to "No address provided."
                            )
                        )
                        return@setMethodCallHandler
                    }

                    thread {
                        val r = connectClassic(address)

                        Handler(Looper.getMainLooper()).post {
                            result.success(r)
                        }
                    }
                }

                "send" -> {
                    val text = call.argument<String>("text") ?: ""

                    val r = sendClassic(text)
                    result.success(r)
                }

                "disconnect" -> {
                    disconnectClassic()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                ActivityCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
    }

    private fun getPairedDevices(): List<Map<String, String>> {
        if (bluetoothAdapter == null) return emptyList()
        if (!hasConnectPermission()) return emptyList()

        return bluetoothAdapter.bondedDevices.map {
            mapOf(
                "name" to (it.name ?: "Unknown Classic Device"),
                "address" to it.address,
                "type" to "Classic"
            )
        }
    }

    private fun connectClassic(address: String): Map<String, Any> {
        if (bluetoothAdapter == null) {
            return mapOf(
                "success" to false,
                "message" to "Bluetooth adapter not available."
            )
        }

        if (!hasConnectPermission()) {
            return mapOf(
                "success" to false,
                "message" to "Missing BLUETOOTH_CONNECT permission."
            )
        }

        return try {
            disconnectClassic()

            val device = bluetoothAdapter.getRemoteDevice(address)

            try {
                bluetoothAdapter.cancelDiscovery()
            } catch (_: Exception) {
            }

            socket = device.createRfcommSocketToServiceRecord(sppUuid)
            socket!!.connect()

            outputStream = socket!!.outputStream

            mapOf(
                "success" to true,
                "message" to "Classic Bluetooth connected."
            )
        } catch (e: Exception) {
            tryReflectionFallback(address, e.message ?: "Unknown error")
        }
    }

    private fun tryReflectionFallback(address: String, originalError: String): Map<String, Any> {
        return try {
            disconnectClassic()

            val device = bluetoothAdapter!!.getRemoteDevice(address)

            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType
            )

            socket = method.invoke(device, 1) as BluetoothSocket
            socket!!.connect()

            outputStream = socket!!.outputStream

            mapOf(
                "success" to true,
                "message" to "Classic Bluetooth connected using fallback socket."
            )
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "message" to "Classic connection failed. Main: $originalError. Fallback: ${e.message}"
            )
        }
    }

    private fun sendClassic(text: String): Map<String, Any> {
        return try {
            if (outputStream == null) {
                return mapOf(
                    "success" to false,
                    "message" to "Not connected."
                )
            }

            outputStream!!.write(text.toByteArray())
            outputStream!!.flush()

            mapOf(
                "success" to true,
                "message" to "Sent: $text"
            )
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "message" to "Send failed: ${e.message}"
            )
        }
    }

    private fun disconnectClassic() {
        try {
            outputStream?.close()
        } catch (_: Exception) {
        }

        try {
            socket?.close()
        } catch (_: Exception) {
        }

        outputStream = null
        socket = null
    }

    override fun onDestroy() {
        disconnectClassic()
        super.onDestroy()
    }
}