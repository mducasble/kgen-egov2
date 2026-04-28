package com.kgeneye.eye.upload

/** Immutable snapshot of the credentials needed to talk to S3. */
data class S3Config(
    val bucket: String,
    val region: String,
    val accessKeyId: String,
    val secretAccessKey: String,
) {
    val isValid: Boolean
        get() = bucket.isNotBlank() && region.isNotBlank() &&
                accessKeyId.isNotBlank() && secretAccessKey.isNotBlank()

    companion object {
        /** Uses credentials from [EmbeddedAwsCredentials] (compile-time constants). */
        fun embedded(): S3Config = S3Config(
            bucket = EmbeddedAwsCredentials.BUCKET,
            region = EmbeddedAwsCredentials.REGION,
            accessKeyId = EmbeddedAwsCredentials.accessKeyId,
            secretAccessKey = EmbeddedAwsCredentials.secretAccessKey,
        )
    }
}
