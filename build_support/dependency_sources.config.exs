project_root = Path.expand("..", __DIR__)
siblings_root = Path.expand("..", project_root)

%{
  deps: %{
    blitz: %{
      path: Path.join(siblings_root, "blitz"),
      github: %{repo: "nshkrdotcom/blitz", branch: "main"},
      hex: "~> 0.3.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    pristine: %{
      path: Path.join(project_root, "apps/pristine_runtime"),
      github: %{repo: "nshkrdotcom/pristine", branch: "main", subdir: "apps/pristine_runtime"},
      hex: "~> 0.2.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    pristine_codegen: %{
      path: Path.join(project_root, "apps/pristine_codegen"),
      github: %{repo: "nshkrdotcom/pristine", branch: "main", subdir: "apps/pristine_codegen"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    pristine_provider_testkit: %{
      path: Path.join(project_root, "apps/pristine_provider_testkit"),
      github: %{
        repo: "nshkrdotcom/pristine",
        branch: "main",
        subdir: "apps/pristine_provider_testkit"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
