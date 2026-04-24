// build/after-pack.cjs
// Electron-builder afterPack hook: apply ad-hoc codesign to the .app bundle.
//
// Why: Nexus has no paid Apple Developer ID, so we can't Developer ID-sign +
// notarize. But Apple Silicon macOS refuses to launch any arm64 binary that
// lacks at least an ad-hoc signature ("killed: 9" / "is damaged"). So we
// sign with identity `-` (ad-hoc) right after electron-builder writes the
// .app but before it wraps into the .dmg.
//
// Combined with `xattr -dr com.apple.quarantine` in the Homebrew cask
// postflight, this gives users a frictionless install without Gatekeeper
// nagging.

const { execSync } = require('child_process');
const path = require('path');

exports.default = async function (context) {
  if (context.electronPlatformName !== 'darwin') return;

  const appName = context.packager.appInfo.productFilename;
  const appPath = path.join(context.appOutDir, `${appName}.app`);

  console.log(`[after-pack] Ad-hoc signing ${appPath}`);
  execSync(
    `codesign --force --deep --sign - --options runtime "${appPath}"`,
    { stdio: 'inherit' }
  );

  // Verify the signature is in place (non-fatal — just log)
  try {
    execSync(`codesign --verify --verbose "${appPath}"`, { stdio: 'inherit' });
  } catch (err) {
    console.warn(`[after-pack] codesign --verify warned: ${err.message}`);
  }
};
