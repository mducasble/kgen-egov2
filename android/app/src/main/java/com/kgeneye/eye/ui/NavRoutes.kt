package com.kgeneye.eye.ui

/** Central list of navigation routes so screens stay loosely coupled. */
object NavRoutes {
    const val LOGIN = "login"
    const val HOME = "home"
    const val SETTINGS = "settings"
    const val WIZARD = "wizard"
    const val SESSIONS = "sessions"
    const val RECORDING = "recording/{sessionId}"

    fun recording(sessionId: String): String = "recording/$sessionId"
}
