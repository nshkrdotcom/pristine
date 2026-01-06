# Configure Logger for test output capture
Logger.configure(level: :debug)

ExUnit.start(capture_log: true)
