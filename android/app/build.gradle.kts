plugins {
    id("com.android.application")
    id("kotlin-android")
    // O Plugin do Flutter deve vir depois dos de Android e Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // O Plugin do Google Services (Firebase)
    id("com.google.gms.google-services") 
}

android {
    // --- CORREÇÃO 1: NOME IGUAL AO JSON ---
    namespace = "br.com.fabiano.solar_insight"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // --- CORREÇÃO 2: ID IGUAL AO JSON ---
        applicationId = "br.com.fabiano.solar_insight"
        
        // Configurações do Flutter
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // --- CORREÇÃO 3: EVITA CRASH POR FALTA DE MEMÓRIA ---
        multiDexEnabled = true 
    }

    buildTypes {
        release {
            // Assinando com a chave de debug por enquanto para testes
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}