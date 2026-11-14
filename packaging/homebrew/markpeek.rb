# Homebrew cask for MarkPeek.
#
# This file lives in the app repo as the template of record. To publish,
# copy it into a tap repository named `homebrew-tap` under your GitHub
# account, at Casks/markpeek.rb. Users then install with:
#
#   brew install --cask turman17/tap/markpeek
#
# After each release, update `version` and `sha256` (scripts/release.sh
# prints both).
cask "markpeek" do
  version "1.0.0"
  sha256 "2dd6899cb4ca3c4d92bae9450459cd617f2df56478c62639d7758aa8aefe20eb"

  url "https://github.com/turman17/MarkPeek/releases/download/v#{version}/MarkPeek-v#{version}.zip"
  name "MarkPeek"
  desc "Styled Markdown in Quick Look, a reader and editor, and PDF export"
  homepage "https://github.com/turman17/MarkPeek"

  depends_on macos: :sonoma

  app "MarkPeek.app"

  postflight do
    system_command "/usr/bin/qlmanage", args: ["-r"]
  end

  caveats <<~EOS
    MarkPeek is not notarized (no paid Apple Developer account).
    After installing, clear the quarantine flag once:

      xattr -dr com.apple.quarantine /Applications/MarkPeek.app

    Then launch the app once. If Finder previews still show raw text, enable
    MarkPeek under System Settings > General > Login Items & Extensions > Quick Look.
  EOS

  zap trash: [
    "~/Library/Group Containers/YJ3UZ772GP.com.markpeek.app.shared",
    "~/Library/Containers/com.markpeek.app",
    "~/Library/Containers/com.markpeek.app.QuickLook",
    "~/Library/Containers/com.markpeek.app.Thumbnail",
  ]
end
