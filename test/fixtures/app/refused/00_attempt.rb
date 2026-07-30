Attempt = ->(probe) {
  begin
    probe.call.to_s
  rescue => e
    e.class.to_s
  end
}
