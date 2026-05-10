project_root = Path.expand("..", __DIR__)
apps_root = Path.expand("..", project_root)

%{
  deps: %{
    pristine: %{
      path: Path.join(apps_root, "pristine_runtime"),
      github: %{repo: "nshkrdotcom/pristine", branch: "main", subdir: "apps/pristine_runtime"},
      hex: "~> 0.2.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
