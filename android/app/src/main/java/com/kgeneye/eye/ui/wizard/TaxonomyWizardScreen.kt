package com.kgeneye.eye.ui.wizard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kgeneye.eye.taxonomy.SessionTaxonomy
import com.kgeneye.eye.taxonomy.Taxonomy
import com.kgeneye.eye.taxonomy.TaxonomyLoader
import com.kgeneye.eye.taxonomy.localizedLabel
import com.kgeneye.eye.ui.SessionDraft

/**
 * Three-step pre-recording wizard, mirroring the iOS scenario→location→activity
 * flow. The viewpoint stage is hidden because the app only ever produces
 * egocentric captures. Verbs are intentionally left empty for the first
 * milestone — backend already tolerates empty arrays.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaxonomyWizardScreen(onBack: () -> Unit, onComplete: () -> Unit) {
    val context = LocalContext.current
    val taxonomy = remember { TaxonomyLoader.load(context) }

    var step by remember { mutableStateOf(0) }
    var bucket by remember { mutableStateOf<Taxonomy.BinaryScenario?>(null) }
    var location by remember { mutableStateOf<Taxonomy.Location?>(null) }
    var category by remember { mutableStateOf<Taxonomy.TaskCategory?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New recording") },
                navigationIcon = {
                    IconButton(onClick = {
                        when (step) {
                            0 -> onBack()
                            else -> step -= 1
                        }
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp)
        ) {
            Text("Step ${step + 1} of 3", style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            when (step) {
                0 -> BucketStep(
                    selected = bucket,
                    onSelect = { bucket = it; step = 1 }
                )
                1 -> LocationStep(
                    taxonomy = taxonomy,
                    bucket = bucket ?: Taxonomy.BinaryScenario.INDOOR,
                    selected = location,
                    onSelect = { location = it; step = 2 },
                )
                2 -> ActivityStep(
                    taxonomy = taxonomy,
                    selected = category,
                    onSelect = { category = it },
                    canContinue = location != null && category != null,
                    onContinue = {
                        val loc = location ?: return@ActivityStep
                        val cat = category ?: return@ActivityStep
                        val bkt = bucket ?: Taxonomy.BinaryScenario.INDOOR
                        val (timeOfDay, hour) = SessionTaxonomy.dayOrNight()
                        SessionDraft.pendingTaxonomy = SessionTaxonomy(
                            schemaVersion = taxonomy.schemaVersion,
                            viewpointCode = "egocentric",
                            scenarioCode = loc.scenario,
                            scenarioBucket = bkt.code,
                            domainCode = loc.domain,
                            locationCode = loc.code,
                            locationLabelPt = loc.labelPt,
                            locationLabelEn = loc.labelEn,
                            taskCategoryCode = cat.code,
                            taskCategoryGroup = cat.group,
                            taskCategoryLabelPt = cat.labelPt,
                            taskCategoryLabelEn = cat.labelEn,
                            timeOfDay = timeOfDay,
                            recordingHour = hour,
                        )
                        onComplete()
                    }
                )
            }
        }
    }
}

@Composable
private fun BucketStep(
    selected: Taxonomy.BinaryScenario?,
    onSelect: (Taxonomy.BinaryScenario) -> Unit,
) {
    Text("Where will this recording take place?", style = MaterialTheme.typography.titleLarge)
    Spacer(Modifier.height(16.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        BucketOption(
            modifier = Modifier.weight(1f),
            title = "Indoor",
            selected = selected == Taxonomy.BinaryScenario.INDOOR,
            onClick = { onSelect(Taxonomy.BinaryScenario.INDOOR) },
        )
        BucketOption(
            modifier = Modifier.weight(1f),
            title = "Outdoor",
            selected = selected == Taxonomy.BinaryScenario.OUTDOOR,
            onClick = { onSelect(Taxonomy.BinaryScenario.OUTDOOR) },
        )
    }
}

@Composable
private fun BucketOption(
    modifier: Modifier,
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val inner: @Composable () -> Unit = {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            if (selected) Icon(Icons.Default.Check, contentDescription = null)
        }
    }
    if (selected) {
        Card(modifier = modifier.height(140.dp), onClick = onClick) { inner() }
    } else {
        OutlinedCard(modifier = modifier.height(140.dp), onClick = onClick) { inner() }
    }
}

@Composable
private fun LocationStep(
    taxonomy: Taxonomy,
    bucket: Taxonomy.BinaryScenario,
    selected: Taxonomy.Location?,
    onSelect: (Taxonomy.Location) -> Unit,
) {
    val locations = remember(bucket) { taxonomy.locationsMatching(bucket) }
    Text("Pick the location", style = MaterialTheme.typography.titleLarge)
    Spacer(Modifier.height(12.dp))
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        items(locations, key = { it.code }) { loc ->
            val isSelected = selected?.code == loc.code
            if (isSelected) {
                Card(modifier = Modifier.fillMaxWidth(), onClick = { onSelect(loc) }) {
                    LocationRow(loc)
                }
            } else {
                OutlinedCard(modifier = Modifier.fillMaxWidth(), onClick = { onSelect(loc) }) {
                    LocationRow(loc)
                }
            }
        }
    }
}

@Composable
private fun LocationRow(loc: Taxonomy.Location) {
    Column(Modifier.padding(14.dp)) {
        Text(loc.localizedLabel(), style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold)
        Text("domain: ${loc.domain} · scenario: ${loc.scenario}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ActivityStep(
    taxonomy: Taxonomy,
    selected: Taxonomy.TaskCategory?,
    onSelect: (Taxonomy.TaskCategory) -> Unit,
    canContinue: Boolean,
    onContinue: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Text("Pick the activity", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(12.dp))
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(taxonomy.taskCategories, key = { it.code }) { cat ->
                val isSelected = selected?.code == cat.code
                if (isSelected) {
                    Card(modifier = Modifier.fillMaxWidth(), onClick = { onSelect(cat) }) {
                        ActivityRow(cat)
                    }
                } else {
                    OutlinedCard(modifier = Modifier.fillMaxWidth(), onClick = { onSelect(cat) }) {
                        ActivityRow(cat)
                    }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = onContinue,
            enabled = canContinue,
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) { Text("Continue") }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun ActivityRow(cat: Taxonomy.TaskCategory) {
    Column(Modifier.padding(14.dp)) {
        Text(cat.localizedLabel(), style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold)
        Text("${cat.group} · ${cat.code}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
