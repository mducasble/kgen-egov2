package com.kgeneye.eye.upload

import android.util.Log
import aws.sdk.kotlin.runtime.auth.credentials.StaticCredentialsProvider
import aws.sdk.kotlin.services.s3.S3Client
import aws.sdk.kotlin.services.s3.model.PutObjectRequest
import aws.smithy.kotlin.runtime.content.ByteStream
import aws.smithy.kotlin.runtime.content.fromFile
import kotlinx.coroutines.delay
import java.io.File

/**
 * Thin wrapper around the AWS SDK for Kotlin's S3 client. Uploads a single
 * file with bounded retry/backoff, mirroring the behaviour of the iOS
 * `S3UploadService`.
 */
class S3UploadService(private val config: S3Config) {

    sealed interface Result {
        data class Success(val attempt: Int) : Result
        data class Failure(val attempt: Int, val error: String) : Result
    }

    suspend fun uploadFile(local: File, s3Key: String): Result {
        var attempt = 0
        var lastError: Throwable? = null

        S3Client.fromEnvironment {
            region = config.region
            credentialsProvider = StaticCredentialsProvider {
                accessKeyId = config.accessKeyId
                secretAccessKey = config.secretAccessKey
            }
        }.use { client ->
            while (attempt < MAX_ATTEMPTS) {
                attempt += 1
                try {
                    client.putObject(
                        PutObjectRequest {
                            bucket = config.bucket
                            key = s3Key
                            body = ByteStream.fromFile(local)
                            contentType = contentTypeFor(local.name)
                            contentLength = local.length()
                        }
                    )
                    return Result.Success(attempt)
                } catch (t: Throwable) {
                    lastError = t
                    Log.w(TAG, "Upload attempt $attempt failed for $s3Key: ${t.message}")
                    if (attempt >= MAX_ATTEMPTS) break
                    delay(backoffMs(attempt))
                }
            }
        }

        return Result.Failure(attempt, lastError?.message ?: "unknown")
    }

    private fun contentTypeFor(name: String): String = when {
        name.endsWith(".mp4") -> "video/mp4"
        name.endsWith(".jsonl") -> "application/x-ndjson"
        name.endsWith(".json") -> "application/json"
        else -> "application/octet-stream"
    }

    private fun backoffMs(attempt: Int): Long =
        (INITIAL_BACKOFF_MS * (1L shl (attempt - 1))).coerceAtMost(MAX_BACKOFF_MS)

    companion object {
        private const val TAG = "S3UploadService"
        private const val MAX_ATTEMPTS = 4
        private const val INITIAL_BACKOFF_MS = 1_000L
        private const val MAX_BACKOFF_MS = 15_000L
    }
}
