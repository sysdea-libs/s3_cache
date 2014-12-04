defmodule S3Cache.Mixfile do
  use Mix.Project

  def project do
    [app: :s3_cache,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps,
     package: [
      contributors: ["Chris Spencer"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/sysdea/s3_cache"}
     ],
     description: "A refreshing cache for S3 files, stored in ETS."]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :httpoison],
     mod: {S3Cache, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [{:httpoison, "~> 0.5"}]
  end
end
