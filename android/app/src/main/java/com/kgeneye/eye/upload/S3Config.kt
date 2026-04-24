package com.kgeneye.eye.upload

import com.kgeneye.eye.settings.AppSettings

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
        fun from(settings: AppSettings.Snapshot): S3Config = S3Config(
            bucket = settings.awsBucket,
            region = settings.awsRegion,
            accessKeyId = settings.awsAccessKeyId,
            secretAccessKey = settings.awsSecretAccessKey,
        )
    }
}
