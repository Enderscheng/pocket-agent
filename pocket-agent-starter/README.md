# Pocket Agent: Siri prototype

Build an iPhone app from Ubuntu using a GitHub-hosted Mac, then install it with SideStore. Requires iOS 16 or later and Siri enabled. These phrases are supplied in English; use English Siri for the initial test.

This is the first milestone: test whether Siri can invoke a native app action and collect spoken input while your phone is locked. It does not yet connect to an AI agent, save tasks, modify calendars, or access Obsidian. No API keys, Apple account credentials, or GitHub secrets are needed for the build.

## 1. Upload the source from Ubuntu

1. Extract pocket-agent-starter.zip.
2. Sign in to GitHub and create a repository named `pocket-agent`. Choose Public for free standard GitHub-hosted build runners. Only the supplied source will be public. Enable Add README to make uploading easier.
3. In the repository, select Add file > Upload files.
4. From INSIDE the extracted pocket-agent-starter folder, upload the `PocketAgent` folder, `scripts` folder, `project.json`, and `build-ios.yml`. Drag the two folders and the two files into the upload area. Commit the upload to the default branch. Do not upload the ZIP or the outer pocket-agent-starter folder.
5. Select Add file > Create new file. Enter `.github/workflows/build-ios.yml` as the full filename.
6. On Ubuntu, open the supplied top-level `build-ios.yml` in a text editor. Copy its entire contents into the new GitHub file and commit it to the default branch.

The ZIP also includes the hidden `.github` directory for people uploading with Git. If you already uploaded that directory, do not create the workflow a second time. The top-level workflow copy is a convenience for browser uploads; only the copy under `.github/workflows` is executed.

Your repository must contain:

```
.github/workflows/build-ios.yml
PocketAgent/PocketAgentApp.swift
PocketAgent/AgentIntents.swift
scripts/build-ios.sh
project.json
```

## 2. Build on GitHub

1. Open your repository's Actions tab.
2. If prompted, enable workflows for this repository.
3. Select Build Pocket Agent, then Run workflow. Choose your default branch and confirm Run workflow.
4. Open the new run and wait for a green check. A first run may take several minutes.
5. On the completed run's summary, find Artifacts and download PocketAgent-IPA. GitHub requires you to be signed in to download it.
6. Extract the downloaded artifact ZIP. Inside is `PocketAgent.ipa`.

The macOS runner uses its default Xcode and installs XcodeGen if needed. XcodeGen turns project.json into an Xcode project. The script builds a device app without signing it and packages it as an IPA. SideStore does the signing on your iPhone. Build dependencies are retrieved from their upstream providers; no backend service is included.

If the run fails, open the red step and copy the first compiler error and the lines around it. Do not try installing the source ZIP: it is not an IPA.

## 3. Install with SideStore

1. On iPhone Safari, sign in to GitHub, open the successful Actions run, and download its PocketAgent-IPA artifact. Save it to Files.
2. In Files, tap the downloaded ZIP to extract it. Locate PocketAgent.ipa inside the extracted folder.
3. Use the same Wi-Fi and LocalDevVPN setup that made your SideStore refresh succeed.
4. Open SideStore > My Apps > + and select PocketAgent.ipa from Files.
5. Let SideStore sign and install it. Open Pocket Agent once from the Home Screen.
6. Keep refreshing it in SideStore before its provisioning expires, just as you do for SideStore itself.

No app icon artwork is included in this first prototype, so the installed icon may be a placeholder.

## 4. Test Siri in two stages

First, with the phone unlocked:

1. Say: "Siri, test Pocket Agent."
2. Expected response: "Pocket Agent is ready."
3. Say: "Siri, capture a task with Pocket Agent."
4. When asked what to capture, say: "Buy milk tomorrow."
5. Expected response: "Received 3 words. Capture test complete."

Then enable Allow Siri When Locked in Settings (the Siri settings section's name depends on iOS version). Lock your phone and repeat both tests with the phone facing away from you so Face ID does not silently unlock it. After restarting the phone, unlock it once before testing.

If Siri does not recognize the app, open Pocket Agent and tap Register Siri shortcuts again. Check Shortcuts > App Shortcuts for Pocket Agent. If needed, create a named shortcut containing only Pocket Agent's Test Connection or Test Task Capture action; do not add an Open App action. Set Task to Ask Each Time for the capture action. Test again unlocked first, then locked.

Record four results: connection unlocked, capture unlocked, connection locked, capture locked. Note the exact message if Siri requests unlocking. A successful connection test alone does not establish that free-form speech collection also works while locked.

## How the lock-screen behavior works

Both actions set `authenticationPolicy = .alwaysAllowed` and `openAppWhenRun = false`. Apple documents alwaysAllowed as allowing an intent while the device is locked. This declares an app policy; it does not override Siri settings, system restrictions, or prove that sideloading and voice input work on a particular device. The prototype deliberately avoids network calls and storage so these do not confuse the first test.

Siri handles voice input. The app only counts whitespace-separated words and returns a short response. The app has no outgoing network calls and does not persist the task text; Siri's own processing remains subject to your Apple settings.

## Next milestone: restricted agent

After both locked tests succeed, connect the capture action to an authenticated HTTPS service on your Ubuntu machine or hosted server. That service must enforce the allowed operations in code, independently of model instructions: for example, append to one Obsidian inbox file or create a limited calendar draft. Treat every request from the locked-phone route as untrusted even when it includes the app's device token. Keep full agent credentials on the service and require authenticated approval for operations beyond the chosen limits. Decide how calendar access and Obsidian synchronization work before implementing those integrations.

## Validation status

Prepared on Ubuntu. The project JSON, build script syntax, file packaging, and required paths were checked locally. This package has not been compiled with Xcode or tested on an iPhone. The GitHub build and your device tests are the next validation steps.

## References

- Apple AppIntent authentication policy: https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy
- Apple App Shortcuts example: https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents
- XcodeGen project specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
- GitHub Actions billing: https://docs.github.com/en/actions/concepts/billing-and-usage
- SideStore documentation: https://docs.sidestore.io/
