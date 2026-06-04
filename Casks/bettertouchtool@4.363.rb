cask "bettertouchtool@4.363" do
  version "4.363,43630"
  sha256 "67ed717e7254c76d6797f9e8a6f2ee9acd0cbca35b31c41099887ea8e00b3135"

  url "https://folivora.ai/releases/btt#{version.csv.first}-#{version.csv.second}.zip"
  name "BetterTouchTool"
  desc "Tool to customise input devices and automate computer systems"
  homepage "https://folivora.ai/"

  livecheck do
    skip "Pinned historical version"
  end

  auto_updates true
  conflicts_with cask: "bettertouchtool"
  depends_on macos: :catalina

  app "BetterTouchTool.app"

  uninstall quit: "com.hegenberg.BetterTouchTool"

  zap trash: [
    "~/Library/Application Support/BetterTouchTool",
    "~/Library/Caches/com.hegenberg.BetterTouchTool",
    "~/Library/Preferences/com.hegenberg.BetterTouchTool.plist",
  ]
end
