App = ->(request) { a = []; 100000.times { a << ("x" * 10000) }; [200, {}, ["never"]] }
