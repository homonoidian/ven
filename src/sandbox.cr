require "./ven/**"

require "benchmark"

lexer = File.read("examples/lexer.ven")

Benchmark.ips do |x|
  x.report("Ven.read") do
    Ven.read("<sandbox>", lexer)
  end
end
