package com.kgeneye.eye.ui.wizard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.kgeneye.eye.taxonomy.SessionTaxonomy
import com.kgeneye.eye.taxonomy.Taxonomy
import com.kgeneye.eye.taxonomy.TaxonomyLoader
import com.kgeneye.eye.taxonomy.TaskVerbsBundle
import com.kgeneye.eye.taxonomy.TaskVerbsLoader
import com.kgeneye.eye.taxonomy.localizedLabel
import com.kgeneye.eye.taxonomy.localizedList
import com.kgeneye.eye.taxonomy.verbDisplayCased
import com.kgeneye.eye.ui.SessionDraft
import com.kgeneye.eye.ui.components.AmbientBackdrop
import com.kgeneye.eye.ui.components.GlassPane
import com.kgeneye.eye.ui.theme.KETokens

/**
 * Four-step pre-recording wizard, mirroring the iOS scenario → location →
 * activity → verbs flow. The viewpoint stage is hidden because the app only
 * ever produces egocentric captures.
 */
@Composable
fun TaxonomyWizardScreen(onBack: () -> Unit, onComplete: () -> Unit) {
    val context = LocalContext.current
    val taxonomy = remember { TaxonomyLoader.load(context) }

    var step by remember { mutableStateOf(0) }
    var bucket by remember { mutableStateOf<Taxonomy.BinaryScenario?>(null) }
    var location by remember { mutableStateOf<Taxonomy.Location?>(null) }
    var category by remember { mutableStateOf<Taxonomy.TaskCategory?>(null) }
    var selectedVerbs by remember { mutableStateOf<Set<Int>>(emptySet()) }

    Box(Modifier.fillMaxSize()) {
        AmbientBackdrop()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 24.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = { if (step == 0) onBack() else step -= 1 }
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = KETokens.Ink1,
                    )
                }
                Column(Modifier.padding(start = 4.dp).weight(1f)) {
                    Text(
                        "New recording",
                        style = MaterialTheme.typography.titleLarge,
                        color = KETokens.Ink1,
                    )
                    Text(
                        "Step ${step + 1} of 4",
                        style = MaterialTheme.typography.labelLarge,
                        color = KETokens.Ink3,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))

            GlassPane(
                modifier = Modifier.fillMaxSize(),
                padding = PaddingValues(18.dp),
            ) {
                when (step) {
                    0 -> BucketStep(
                        selected = bucket,
                        onSelect = { bucket = it; step = 1 },
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
                        onSelect = {
                            if (category?.code != it.code) {
                                selectedVerbs = emptySet()
                            }
                            category = it
                        },
                        canContinue = category != null,
                        onContinue = { step = 3 },
                    )
                    else -> VerbStep(
                        category = category,
                        selected = selectedVerbs,
                        onToggle = { index ->
                            selectedVerbs = if (selectedVerbs.contains(index)) {
                                selectedVerbs - index
                            } else {
                                selectedVerbs + index
                            }
                        },
                        onContinue = { verbEntry, sortedIndices ->
                            val loc = location ?: return@VerbStep
                            val cat = category ?: return@VerbStep
                            val bkt = bucket ?: Taxonomy.BinaryScenario.INDOOR
                            val (timeOfDay, hour) = SessionTaxonomy.dayOrNight()

                            val verbsPt: List<String>
                            val verbsEn: List<String>
                            val verbsEs: List<String>
                            if (verbEntry != null && sortedIndices.isNotEmpty()) {
                                verbsPt = sortedIndices.map { verbEntry.verbsPt[it] }
                                verbsEn = sortedIndices.map { verbEntry.verbsEn[it] }
                                verbsEs = sortedIndices.map { verbEntry.verbsEs[it] }
                            } else {
                                verbsPt = emptyList(); verbsEn = emptyList(); verbsEs = emptyList()
                            }

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
                                selectedVerbsPt = verbsPt,
                                selectedVerbsEn = verbsEn,
                                selectedVerbsEs = verbsEs,
                                timeOfDay = timeOfDay,
                                recordingHour = hour,
                            )
                            onComplete()
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun BucketStep(
    selected: Taxonomy.BinaryScenario?,
    onSelect: (Taxonomy.BinaryScenario) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            "Where will this recording take place?",
            style = MaterialTheme.typography.titleLarge,
            color = KETokens.Ink1,
        )
        Spacer(Modifier.height(20.dp))
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
}

@Composable
private fun BucketOption(
    modifier: Modifier,
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    SelectableGlassTile(
        modifier = modifier.height(140.dp),
        selected = selected,
        onClick = onClick,
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = KETokens.Ink1,
            )
            if (selected) {
                Spacer(Modifier.height(6.dp))
                Icon(Icons.Default.Check, contentDescription = null, tint = KETokens.Ink1)
            }
        }
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
    Column(Modifier.fillMaxSize()) {
        Text(
            "Pick the location",
            style = MaterialTheme.typography.titleLarge,
            color = KETokens.Ink1,
        )
        Spacer(Modifier.height(12.dp))
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            items(locations, key = { it.code }) { loc ->
                SelectableGlassTile(
                    modifier = Modifier.fillMaxWidth(),
                    selected = selected?.code == loc.code,
                    onClick = { onSelect(loc) },
                ) { LocationRow(loc) }
            }
        }
    }
}

@Composable
private fun LocationRow(loc: Taxonomy.Location) {
    Column(Modifier.padding(14.dp)) {
        Text(
            loc.localizedLabel(),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = KETokens.Ink1,
        )
        Text(
            "domain: ${loc.domain} · scenario: ${loc.scenario}",
            style = MaterialTheme.typography.bodySmall,
            color = KETokens.Ink2,
        )
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
        Text(
            "Pick the activity",
            style = MaterialTheme.typography.titleLarge,
            color = KETokens.Ink1,
        )
        Spacer(Modifier.height(12.dp))
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(taxonomy.taskCategories, key = { it.code }) { cat ->
                SelectableGlassTile(
                    modifier = Modifier.fillMaxWidth(),
                    selected = selected?.code == cat.code,
                    onClick = { onSelect(cat) },
                ) { ActivityRow(cat) }
            }
        }
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = onContinue,
            enabled = canContinue,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(22.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = KETokens.AccentGreen.copy(alpha = 0.85f),
                contentColor = KETokens.Ink1,
                disabledContainerColor = KETokens.GhostTint.copy(alpha = 0.4f),
                disabledContentColor = KETokens.Ink3,
            ),
        ) { Text("Continue") }
        Spacer(Modifier.height(6.dp))
    }
}

@Composable
private fun ActivityRow(cat: Taxonomy.TaskCategory) {
    Column(Modifier.padding(14.dp)) {
        Text(
            cat.localizedLabel(),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = KETokens.Ink1,
        )
        Text(
            "${cat.group} · ${cat.code}",
            style = MaterialTheme.typography.bodySmall,
            color = KETokens.Ink2,
        )
    }
}

@Composable
private fun VerbStep(
    category: Taxonomy.TaskCategory?,
    selected: Set<Int>,
    onToggle: (Int) -> Unit,
    onContinue: (TaskVerbsBundle.Entry?, List<Int>) -> Unit,
) {
    val context = LocalContext.current
    val entry = remember(category?.code) {
        category?.let { TaskVerbsLoader.verbs(context, it.code) }
    }
    val labels = remember(entry) { entry?.localizedList().orEmpty() }
    val canContinue = entry == null || labels.isEmpty() || selected.isNotEmpty()

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            "Pick the actions",
            style = MaterialTheme.typography.titleLarge,
            color = KETokens.Ink1,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "Select the actions you will perform in this recording.",
            style = MaterialTheme.typography.bodySmall,
            color = KETokens.Ink2,
        )
        Spacer(Modifier.height(12.dp))

        if (entry == null || labels.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxWidth().weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "No verb list for this activity yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = KETokens.Ink2,
                )
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(labels.size) { i ->
                    val on = selected.contains(i)
                    SelectableGlassTile(
                        modifier = Modifier.fillMaxWidth(),
                        selected = on,
                        onClick = { onToggle(i) },
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                labels[i].verbDisplayCased(),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Medium,
                                color = KETokens.Ink1,
                                modifier = Modifier.weight(1f),
                            )
                            if (on) {
                                Icon(Icons.Default.Check, contentDescription = null, tint = KETokens.Ink1)
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        Button(
            onClick = { onContinue(entry, selected.sorted()) },
            enabled = canContinue,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(22.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = KETokens.AccentBlue.copy(alpha = 0.85f),
                contentColor = KETokens.Ink1,
                disabledContainerColor = KETokens.GhostTint.copy(alpha = 0.4f),
                disabledContentColor = KETokens.Ink3,
            ),
        ) { Text("Continue") }
        Spacer(Modifier.height(6.dp))
    }
}

/** Small glass tile with an accent rim when selected. */
@Composable
private fun SelectableGlassTile(
    modifier: Modifier = Modifier,
    selected: Boolean,
    cornerRadius: Dp = 18.dp,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(cornerRadius)
    val rim = if (selected) KETokens.AccentBlue else KETokens.EdgeBright.copy(alpha = 0.5f)
    val fill = if (selected) KETokens.AccentBlue.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.4f)
    Box(
        modifier = modifier
            .clip(shape)
            .background(fill)
            .border(1.dp, rim, shape)
            .clickable(onClick = onClick),
    ) { content() }
}
