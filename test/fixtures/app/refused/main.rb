Prober = ->(request) {
  body = JSON.generate(
    "allowed" => Attempt.call(-> { Time.now.class }),
    "refused_clock" => Attempt.call(-> { Time.at(0) }),
    "refused_entropy" => Attempt.call(-> { Random.seed }),
    "refused_request" => Attempt.call(-> { request.env })
  )
  [200, { "content-type" => "application/json" }, [body]]
}
