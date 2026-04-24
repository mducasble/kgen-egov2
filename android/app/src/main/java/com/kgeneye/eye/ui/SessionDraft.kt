package com.kgeneye.eye.ui

import com.kgeneye.eye.taxonomy.SessionTaxonomy

/**
 * In-memory handoff between the taxonomy wizard and the recording screen.
 * Kept process-local (lost if the app is killed between the two screens) —
 * parity with the iOS wizard that also just hands the struct to the
 * orchestrator without persisting an intermediate file.
 */
object SessionDraft {
    @Volatile var pendingTaxonomy: SessionTaxonomy? = null
}
