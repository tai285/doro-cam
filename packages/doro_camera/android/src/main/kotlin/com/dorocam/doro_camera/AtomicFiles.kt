package com.dorocam.doro_camera

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Durable file writes (NFR-002): data goes to a temp file in the same directory, is flushed to disk,
 * then renamed into place. A crash leaves either the complete file or none, plus a `.doro-tmp` leftover
 * that [cleanStale] removes on the next start (docs/specs/camera.md edge case "app kill during capture").
 */
object AtomicFiles {
    const val TEMP_SUFFIX = ".doro-tmp"

    /** Directory plus a plain file name; rejects anything that could escape the directory. */
    fun target(dir: String, name: String): File {
        if (name.isEmpty() || name.contains('/') || name.contains('\\') || name == "." || name == ".." || name.contains("..")) {
            throw CameraException("unsupported_configuration", "Invalid file name: $name")
        }
        val directory = File(dir)
        if (!directory.isDirectory) throw CameraException("unsupported_configuration", "Output directory does not exist: $dir")
        return File(directory, name)
    }

    fun tempFor(target: File): File = File(target.parentFile, "${target.name}$TEMP_SUFFIX")

    fun write(target: File, bytes: ByteArray) {
        val temp = tempFor(target)
        try {
            FileOutputStream(temp).use { out ->
                out.write(bytes)
                out.flush()
                out.fd.sync()
            }
            commit(temp, target)
        } catch (e: IOException) {
            temp.delete()
            throw ioToCamera(e)
        }
    }

    /** Streams into a temp file and commits it; [block] writes to the stream. */
    fun write(target: File, block: (java.io.OutputStream) -> Unit) {
        val temp = tempFor(target)
        try {
            FileOutputStream(temp).use { out ->
                block(out)
                out.flush()
                out.fd.sync()
            }
            commit(temp, target)
        } catch (e: IOException) {
            temp.delete()
            throw ioToCamera(e)
        }
    }

    fun commit(temp: File, target: File) {
        if (target.exists() && !target.delete()) throw IOException("Cannot replace ${target.name}")
        if (!temp.renameTo(target)) throw IOException("Cannot move ${temp.name} into place")
    }

    fun ioToCamera(e: IOException): CameraException {
        val text = (e.message ?: "").lowercase()
        return if ("enospc" in text || "no space" in text) {
            CameraException("storage_full", "The device is out of storage", e)
        } else {
            CameraException("capture_failed", "Could not write the file: ${e.message}", e)
        }
    }

    /** Removes leftovers of an interrupted capture. Returns how many were removed. */
    fun cleanStale(dir: File, olderThanMs: Long = 0, now: Long = System.currentTimeMillis()): Int {
        val leftovers = dir.listFiles { f -> f.isFile && f.name.endsWith(TEMP_SUFFIX) && now - f.lastModified() >= olderThanMs } ?: return 0
        return leftovers.count { it.delete() }
    }
}
