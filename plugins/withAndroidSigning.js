// @ts-check
const { withAppBuildGradle } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

/**
 * Expo config plugin that injects a release signingConfig into the generated
 * android/app/build.gradle. Credentials are read from `signing.properties`
 * at the project root — never committed, fully project-local.
 *
 * Create signing.properties in the project root (it is gitignored):
 *   RELEASE_KEY_ALIAS=m3u-tv
 *   RELEASE_STORE_PASSWORD=yourpassword
 *   RELEASE_KEY_PASSWORD=yourpassword
 *
 * The keystore is expected at <project-root>/release.keystore.
 *
 * At prebuild time the plugin copies signing.properties into android/ so
 * Gradle can load it at build time. No plaintext credentials are written into
 * build.gradle itself. If either file is missing the plugin does nothing,
 * leaving the release build signed with the debug key so contributors without
 * the production keystore can still build a sideloadable test APK.
 *
 * @param {import('@expo/config-types').ExpoConfig} config
 */
const withAndroidSigning = (config) =>
  withAppBuildGradle(config, (mod) => {
    let contents = mod.modResults.contents;

    // Idempotency guard — don't add twice
    if (contents.includes('signingConfigs.release')) {
      return mod;
    }

    const projectRoot = mod.modResults.path
      ? path.resolve(path.dirname(mod.modResults.path), '..', '..')
      : process.cwd();

    const propsFile = path.join(projectRoot, 'signing.properties');
    const keystoreFile = path.join(projectRoot, 'release.keystore');

    if (!fs.existsSync(propsFile) || !fs.existsSync(keystoreFile)) {
      console.warn(
        '\n[withAndroidSigning] signing.properties or release.keystore not found — ' +
          'falling back to debug signing. The APK will install but cannot be published.\n',
      );
      return mod;
    }

    // Copy signing.properties into android/ so Gradle can read it at build time.
    // The file is added to android/.gitignore so it is never committed.
    const androidDir = path.join(projectRoot, 'android');
    fs.copyFileSync(propsFile, path.join(androidDir, 'signing.properties'));

    const androidGitignore = path.join(androidDir, '.gitignore');
    if (fs.existsSync(androidGitignore)) {
      const existing = fs.readFileSync(androidGitignore, 'utf8');
      if (!existing.includes('signing.properties')) {
        fs.appendFileSync(androidGitignore, '\n# Release signing credentials (copied by withAndroidSigning plugin)\nsigning.properties\n');
      }
    }

    // Inject a Gradle snippet that loads signing.properties into a Properties
    // object. build.gradle will reference properties by key — no plaintext.
    const propsLoader = `
def releaseSigningProps = new Properties()
def releaseSigningFile = rootProject.file('signing.properties')
if (releaseSigningFile.exists()) {
    releaseSigningFile.withInputStream { releaseSigningProps.load(it) }
}
`;

    // Insert the loader just before the android { block
    contents = contents.replace(/^(android\s*\{)/m, `${propsLoader}\n$1`);

    // Keystore lives at project root; relative to android/app/ that is ../../
    const keystorePath = '../../release.keystore';

    // Add a release signingConfig block after the existing debug one
    contents = contents.replace(
      /signingConfigs\s*\{([\s\S]*?debug\s*\{[\s\S]*?\})\s*\}/,
      (match, debugBlock) =>
        `signingConfigs {${debugBlock}
        release {
            storeFile file('${keystorePath}')
            storePassword releaseSigningProps['RELEASE_STORE_PASSWORD'] ?: ''
            keyAlias releaseSigningProps['RELEASE_KEY_ALIAS'] ?: ''
            keyPassword releaseSigningProps['RELEASE_KEY_PASSWORD'] ?: ''
        }
    }`,
    );

    // Point the release buildType at the new signingConfig
    contents = contents.replace(
      /(buildTypes\s*\{[\s\S]*?release\s*\{[\s\S]*?)signingConfig\s+signingConfigs\.debug/,
      '$1signingConfig signingConfigs.release',
    );

    mod.modResults.contents = contents;
    return mod;
  });

module.exports = withAndroidSigning;
