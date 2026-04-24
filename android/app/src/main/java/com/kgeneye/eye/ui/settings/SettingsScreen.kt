package com.kgeneye.eye.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kgeneye.eye.settings.AppSettings

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val appSettings = remember { AppSettings.get(context) }
    val snapshot by appSettings.state.collectAsStateWithLifecycle()

    var bucket by remember { mutableStateOf(snapshot.awsBucket) }
    var region by remember { mutableStateOf(snapshot.awsRegion) }
    var accessKey by remember { mutableStateOf(snapshot.awsAccessKeyId) }
    var secretKey by remember { mutableStateOf(snapshot.awsSecretAccessKey) }
    var name by remember { mutableStateOf(snapshot.contributorName) }
    var country by remember { mutableStateOf(snapshot.contributorCountry) }
    var campaign by remember { mutableStateOf(snapshot.campaign.ifBlank { AppSettings.DEFAULT_CAMPAIGN }) }

    var showSecret by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding)
                .padding(horizontal = 20.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Spacer(Modifier.height(8.dp))

            SectionHeader("Contributor")
            OutlinedTextField(value = name, onValueChange = { name = it },
                label = { Text("Name") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true)
            OutlinedTextField(value = country, onValueChange = { country = it },
                label = { Text("Country (ISO, e.g. BR)") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text))

            SectionHeader("Campaign")
            OutlinedTextField(value = campaign, onValueChange = { campaign = it },
                label = { Text("Campaign tag") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true)

            SectionHeader("AWS S3")
            OutlinedTextField(value = bucket, onValueChange = { bucket = it },
                label = { Text("Bucket") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(value = region, onValueChange = { region = it },
                label = { Text("Region (e.g. us-east-1)") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true)
            OutlinedTextField(value = accessKey, onValueChange = { accessKey = it },
                label = { Text("Access key id") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true)
            OutlinedTextField(value = secretKey, onValueChange = { secretKey = it },
                label = { Text("Secret access key") },
                modifier = Modifier.fillMaxWidth(), singleLine = true,
                visualTransformation = if (showSecret) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
            androidx.compose.material3.TextButton(onClick = { showSecret = !showSecret }) {
                Text(if (showSecret) "Hide secret" else "Show secret")
            }

            Spacer(Modifier.height(12.dp))
            Button(
                onClick = {
                    appSettings.update {
                        copy(
                            awsBucket = bucket, awsRegion = region,
                            awsAccessKeyId = accessKey, awsSecretAccessKey = secretKey,
                            contributorName = name, contributorCountry = country,
                            campaign = campaign.ifBlank { AppSettings.DEFAULT_CAMPAIGN },
                        )
                    }
                    onBack()
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) { Text("Save") }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Spacer(Modifier.height(8.dp))
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.fillMaxWidth())
}
