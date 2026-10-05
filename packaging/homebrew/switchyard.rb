# Draft cask for a future submission to Homebrew/homebrew-cask (once Switchyard meets its
# notability bar). Fill in @VERSION@ and @SHA256@ (of the release zip); it passes `brew style`
# and `brew audit --online`.
cask "switchyard" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/kevinebaugh/switchyard/releases/download/v#{version}/Switchyard-#{version}.zip"
  name "Switchyard"
  desc "Opens every link in the right browser profile"
  homepage "https://github.com/kevinebaugh/switchyard"

  # Switchyard updates itself with Sparkle.
  auto_updates true
  depends_on macos: :tahoe

  app "Switchyard.app"

  zap trash: [
    "~/Library/Application Support/Switchyard",
    "~/Library/Caches/com.kevinebaugh.switchyard",
    "~/Library/HTTPStorages/com.kevinebaugh.switchyard",
    "~/Library/Preferences/com.kevinebaugh.switchyard.plist",
  ]
end
