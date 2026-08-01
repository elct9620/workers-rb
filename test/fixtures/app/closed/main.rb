Attempt = ->(probe) {
  begin
    probe.call.to_s
  rescue => e
    "#{e.class}: #{e.message}"
  end
}

App = ->(env) {
  body = JSON.generate(
    "environment" => Attempt.call(-> { ENV["PATH"] }),
    "filesystem" => Attempt.call(-> { File.read("/etc/hosts") }),
    "directory" => Attempt.call(-> { Dir.pwd }),
    "network" => Attempt.call(-> { TCPSocket.new("127.0.0.1", 80) }),
    "shell" => Attempt.call(-> { system("id") })
  )
  [200, { "content-type" => "application/json" }, [body]]
}
