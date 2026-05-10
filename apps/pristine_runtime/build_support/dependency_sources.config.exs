project_root = Path.expand("..", __DIR__)
siblings_root = Path.expand("../../..", project_root)

%{
  deps: %{
    execution_plane: %{
      path: Path.join(siblings_root, "execution_plane/core/execution_plane"),
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    execution_plane_http: %{
      path: Path.join(siblings_root, "execution_plane/protocols/execution_plane_http"),
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "protocols/execution_plane_http"
      },
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
