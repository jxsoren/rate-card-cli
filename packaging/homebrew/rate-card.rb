# Homebrew formula for rate-card.
#
# This file lives here so it is versioned alongside the gem it installs; the
# copy that users actually install from is Formula/rate-card.rb in the tap repo
# (jxsoren/homebrew-tools -- not yet created). bin/release copies it across on
# every release.
#
# Runtime gems are fetched by `gem install` at install time rather than being
# pinned as `resource` blocks. Homebrew core would reject that, a tap does not,
# and it matters here: bubbletea, bubbles and lipgloss ship precompiled
# per-platform native binaries that `gem install` selects correctly and a
# vendored resource list would pin to one architecture.
class RateCard < Formula
  desc "Interactive CLI that builds a shipping rate card from the eHub API"
  homepage "https://github.com/jxsoren/rate-card-cli"
  url "https://rubygems.org/downloads/rate-card-0.1.1.gem"
  sha256 "7519eaf0f768e81484a7361fd7ccd8b75a93d4d5bde992295a01b4a1fa601b03"
  license "MIT"

  depends_on "ruby"

  def install
    # GEM_PATH is confined to libexec so dependency resolution cannot satisfy
    # itself from the user's own gems -- everything is vendored in the keg, and
    # the tool is immune to whatever rbenv/rvm setup the user has.
    ENV["GEM_HOME"] = libexec
    ENV["GEM_PATH"] = libexec

    system formula_opt_bin("ruby")/"gem", "install", cached_download,
           "--no-document", "--install-dir", libexec

    (bin/"rate-card").write_env_script libexec/"bin/rate-card",
                                       GEM_HOME: libexec,
                                       GEM_PATH: libexec,
                                       PATH:     "#{formula_opt_bin("ruby")}:$PATH"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rate-card --version")
    assert_match "Usage: rate-card", shell_output("#{bin}/rate-card --help")
  end
end
