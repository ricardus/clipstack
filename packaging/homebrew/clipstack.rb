# Copy into github.com/ricardus/homebrew-tap as Casks/clipstack.rb after each
# release, with version and sha256 taken from the release's .sha256 file.
cask "clipstack" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/ricardus/clipstack/releases/download/v#{version}/Clipstack-v#{version}.zip"
  name "Clipstack"
  desc "Local clipboard and screenshot history for the menu bar"
  homepage "https://ricardus.github.io/clipstack/"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Clipstack.app"

  # Not notarized: drop the quarantine flag so Gatekeeper does not block the
  # first launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Clipstack.app"]
  end

  uninstall quit: "io.github.ricardus.clipstack"

  zap trash: [
    "~/Library/Application Support/Clipstack",
    "~/Library/Preferences/io.github.ricardus.clipstack.plist",
  ]
end
