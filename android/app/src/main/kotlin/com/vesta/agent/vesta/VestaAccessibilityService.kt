package com.vesta.agent.vesta

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

class VestaAccessibilityService : AccessibilityService() {

    companion object {
        var instance: VestaAccessibilityService? = null
        const val ACTION_CLICK = "ACTION_CLICK"
        const val ACTION_TYPE_TEXT = "ACTION_TYPE_TEXT"
        private const val TAG = "VestaAccessibility"
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "Service Connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Future: listen to specific app events
    }

    override fun onInterrupt() {
        Log.i(TAG, "Service Interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    /** Simulate a tap gesture at (x, y) coordinates. */
    fun performClickAt(x: Float, y: Float): Boolean {
        val path = Path()
        path.moveTo(x, y)
        val builder = GestureDescription.Builder()
        val strokeDescription = GestureDescription.StrokeDescription(path, 0, 100)
        builder.addStroke(strokeDescription)
        return dispatchGesture(builder.build(), null, null)
    }

    /** Simulate a swipe gesture from (x1,y1) to (x2,y2) over durationMs. */
    fun performSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300): Boolean {
        val path = Path()
        path.moveTo(x1, y1)
        path.lineTo(x2, y2)
        val builder = GestureDescription.Builder()
        builder.addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
        return dispatchGesture(builder.build(), null, null)
    }

    /**
     * Set text in the currently focused input using ACTION_SET_TEXT.
     * Returns true if successful.
     */
    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = findFocusedInput(root) ?: return false
        val args = android.os.Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /** Global back action via AccessibilityService API. */
    fun performBack(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)

    /** Global home action via AccessibilityService API. */
    fun performHome(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)

    /** Opens recent apps. */
    fun performRecents(): Boolean = performGlobalAction(GLOBAL_ACTION_RECENTS)

    /**
     * Scan the active window's node tree and return a JSON string array
     * of interactable elements: {"label": "...", "x": ..., "y": ..., "type": "..."}.
     * This is FAR more accurate than raw screenshot analysis.
     */
    fun getScreenNodes(): String {
        val root = rootInActiveWindow ?: return "[]"
        val nodes = JSONArray()
        traverseNodes(root, nodes)
        return nodes.toString()
    }

    private fun traverseNodes(node: AccessibilityNodeInfo?, result: JSONArray) {
        if (node == null) return
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        val label = when {
            !node.text.isNullOrBlank() -> node.text.toString()
            !node.contentDescription.isNullOrBlank() -> node.contentDescription.toString()
            !node.hintText.isNullOrBlank() -> node.hintText.toString()
            else -> null
        }
        if (label != null && (node.isClickable || node.isEditable || node.isFocusable)) {
            val obj = JSONObject()
            obj.put("label", label)
            obj.put("x", bounds.centerX())
            obj.put("y", bounds.centerY())
            obj.put("type", when {
                node.isEditable -> "input"
                node.isClickable -> "button"
                else -> "text"
            })
            result.put(obj)
        }
        for (i in 0 until node.childCount) {
            traverseNodes(node.getChild(i), result)
        }
    }

    private fun findFocusedInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (root.isEditable && root.isFocused) return root
        for (i in 0 until root.childCount) {
            val found = findFocusedInput(root.getChild(i) ?: continue)
            if (found != null) return found
        }
        return null
    }

    /** Takes a hardware-safe screenshot. Requires API 30+. */
    fun captureScreen(callback: (ByteArray?) -> Unit) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        try {
                            val hwBitmap = android.graphics.Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer, screenshot.colorSpace
                            )
                            if (hwBitmap != null) {
                                // CRITICAL: copy to software bitmap before JPEG compression
                                val swBitmap = hwBitmap.copy(android.graphics.Bitmap.Config.ARGB_8888, false)
                                val out = java.io.ByteArrayOutputStream()
                                swBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 60, out)
                                callback(out.toByteArray())
                                swBitmap.recycle()
                                hwBitmap.recycle()
                            } else {
                                callback(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Screenshot error: ${e.message}")
                            callback(null)
                        }
                    }
                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "Screenshot failed: $errorCode")
                        callback(null)
                    }
                })
        } else {
            callback(null)
        }
    }
}
