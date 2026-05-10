project_root = Path.expand("..", __DIR__)
apps_root = Path.expand("..", project_root)

%{
  deps: %{
    pristine_codegen: %{
      path: Path.join(apps_root, "pristine_codegen"),
      github: %{repo: "nshkrdotcom/pristine", branch: "main", subdir: "apps/pristine_codegen"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
