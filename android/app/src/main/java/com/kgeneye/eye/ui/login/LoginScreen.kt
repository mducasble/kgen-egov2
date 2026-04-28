package com.kgeneye.eye.ui.login

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.kgeneye.eye.auth.AuthRepository
import com.kgeneye.eye.ui.components.AmbientBackdrop
import com.kgeneye.eye.ui.components.BrandLockup
import com.kgeneye.eye.ui.components.GlassLogoBadge
import com.kgeneye.eye.ui.components.GlassPane
import com.kgeneye.eye.ui.theme.KETokens

@Composable
fun LoginScreen(auth: AuthRepository) {
    val context = LocalContext.current
    val message by auth.message.collectAsStateWithLifecycle()

    var signupMode by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var fullName by remember { mutableStateOf("") }
    var country by remember { mutableStateOf("") }
    var city by remember { mutableStateOf("") }
    var referralCode by remember { mutableStateOf("") }

    Box(Modifier.fillMaxSize()) {
        AmbientBackdrop()

        GlassPane(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp, vertical = 24.dp),
            padding = PaddingValues(horizontal = 44.dp, vertical = 28.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.height(34.dp))
                GlassLogoBadge()
                Spacer(Modifier.height(18.dp))
                BrandLockup()
                Spacer(Modifier.height(28.dp))

                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    AuthField(
                        value = email,
                        onChange = { email = it },
                        label = "Email",
                        keyboardType = KeyboardType.Email,
                    )
                    AuthField(
                        value = password,
                        onChange = { password = it },
                        label = "Password",
                        keyboardType = KeyboardType.Password,
                        secure = true,
                    )
                    if (signupMode) {
                        AuthField(value = fullName, onChange = { fullName = it }, label = "Full name")
                        AuthField(value = country, onChange = { country = it }, label = "Country (ISO, e.g. IN)")
                        AuthField(value = city, onChange = { city = it }, label = "City")
                        AuthField(
                            value = referralCode,
                            onChange = { referralCode = it },
                            label = "Referral code (optional)",
                        )
                    }
                }

                if (!message.isNullOrBlank()) {
                    Spacer(Modifier.height(10.dp))
                    Text(
                        message.orEmpty(),
                        color = KETokens.AccentRed,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                Spacer(Modifier.height(14.dp))
                Button(
                    onClick = {
                        auth.clearMessage()
                        if (signupMode) {
                            auth.signup(
                                email = email,
                                password = password,
                                fullName = fullName.blankToNull(),
                                country = country.blankToNull(),
                                city = city.blankToNull(),
                                referralCode = referralCode.blankToNull(),
                            )
                        } else {
                            auth.login(email, password)
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = KETokens.AccentGreen.copy(alpha = 0.72f),
                        contentColor = KETokens.Ink1,
                    ),
                ) {
                    Text(if (signupMode) "Create account" else "Log in")
                }

                TextButton(onClick = { auth.forgotPassword(email) }) {
                    Text("Forgot my password", color = KETokens.AccentBlue)
                }
                TextButton(onClick = { signupMode = !signupMode }) {
                    Text(
                        if (signupMode) "Already have an account? Log in" else "Need an account? Sign up",
                        color = KETokens.Ink2,
                    )
                }
            }
        }
    }
}

@Composable
private fun AuthField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    secure: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        visualTransformation = if (secure) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        leadingIcon = {
            androidx.compose.material3.Icon(
                imageVector = if (secure) Icons.AutoMirrored.Filled.Login else Icons.Filled.AccountCircle,
                contentDescription = null,
            )
        },
        shape = RoundedCornerShape(16.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = KETokens.AccentBlue,
            unfocusedBorderColor = KETokens.Ink3,
            focusedLabelColor = KETokens.Ink1,
            unfocusedLabelColor = KETokens.Ink2,
            focusedTextColor = KETokens.Ink1,
            unfocusedTextColor = KETokens.Ink1,
            cursorColor = KETokens.Ink1,
            focusedContainerColor = Color.White.copy(alpha = 0.55f),
            unfocusedContainerColor = Color.White.copy(alpha = 0.35f),
        ),
    )
}

private fun String.blankToNull(): String? =
    trim().takeIf { it.isNotEmpty() }
