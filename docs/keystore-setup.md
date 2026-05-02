# Keystore Setup — One-Time

This is the **one-time** step that lets GitHub Actions sign release APKs. Done once on Termux on your phone, four secrets pasted into GitHub, then forgotten forever.

> **Skip for first build.** The pipeline ships unsigned debug APKs by default, which install fine for personal testing. You only need the keystore once you're publishing to alpha users or to Play Store.

## 1. Generate the keystore (Termux)

Install OpenJDK in Termux if not already:

```
pkg install openjdk-21
```

Generate the keystore:

```
keytool -genkey -v \
  -keystore lumin-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias lumin
```

Answer the prompts (use the same password for keystore + key when asked).

## 2. Encode keystore as base64

```
base64 lumin-release.jks > lumin-keystore.b64
cat lumin-keystore.b64
```

Copy the entire output.

## 3. Add four GitHub Secrets

Go to https://github.com/mkmk749278/lumin-app/settings/secrets/actions and add:

| Name | Value |
|---|---|
| ANDROID_KEYSTORE_B64 | (paste the base64 string) |
| ANDROID_KEYSTORE_PASSWORD | (your password) |
| ANDROID_KEY_ALIAS | lumin |
| ANDROID_KEY_PASSWORD | (same as keystore password) |

## 4. Backup the keystore

**Save lumin-release.jks to multiple places** — Google Drive, USB, Telegram saved messages. If you lose it, you can never sign updates with the same identity.
