# Dialyzer ignore patterns
# These are legitimate warnings that we're intentionally suppressing

[
  # MockServer uses Bandit and ThousandIsland which are only available in test environment
  {"lib/pristine/test/mock_server.ex", :unknown_function}
]
