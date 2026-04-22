package com.kgeneye.eye

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kgeneye.eye.databinding.ActivityMainBinding

/**
 * KGeN Eye — Android shell. Capture / upload / taxonomy will mirror iOS rules
 * under [../EgoCapture](../) and shared backend contracts in [../serverless/](../serverless/).
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
    }
}
