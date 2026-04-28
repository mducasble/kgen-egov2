package com.kgeneye.eye.upload

/**
 * Public-facing AWS credentials used by the upload pipeline.
 *
 * The access key / secret live in a sibling file `EmbeddedAwsSecrets.kt`
 * which is **gitignored**. If you just cloned this repo, copy
 * `EmbeddedAwsSecrets.kt.example` to `EmbeddedAwsSecrets.kt` and fill in
 * the real IAM credentials before building.
 */
object EmbeddedAwsCredentials {
    const val BUCKET = "kaivideo"
    const val REGION = "us-east-1"

    val accessKeyId: String get() = EmbeddedAwsSecrets.accessKeyId
    val secretAccessKey: String get() = EmbeddedAwsSecrets.secretAccessKey
}
