require "./lib"

reader = Ven::Reader.new(
  <<-EOF
  distinct hello;

  expose std;
  expose a.b.c;
  expose d.e.f;

  fun add(x, y) =
    say("add", x)(-1) + say("to", y)(-1);

  result = add(1, 2);
  say(result)

  EOF
)

puts "distinct (should be: hello): #{reader.distinct?.try &.join(".")}"
puts "exposes (should be: std, a.b.c, d.e.f): #{reader.exposes.map(&.join(".")).join(", ")}"

quotes = reader.read

puts Ven::Suite::Detree.detree(quotes)

# Reader.read

chunks = [] of Ven::Suite::Chunk

a = Ven::Program.new("1 + 1", file: "a").run(chunks)
b = Ven::Program.new("2 + 2", file: "b").run(chunks)

puts a, b

puts chunks.join("\n")

# Running the calculator is pretty easy now:
# hub = Ven::Suite::Context::Hub.new
# hub.extend(Ven::Library::Internal.new)
# source = File.read("examples/calculator.ven")
# Ven::Program.new(source, file: "examples/calculator.ven", hub: hub).run


tests =
  # Dir["examples/*.ven"] +
  Dir["test/**/[^_]*.ven"]
  # Dir["std/**/*.ven"]

tests.each do |test|
  source = File.read(test)

  c_context = Ven::Suite::Context::Compiler.new
  m_context = Ven::Suite::Context::Machine.new
  Ven::Library::Internal.new.load(c_context, m_context)

  begin
    took = Time.measure do
      quotes = Ven::Reader.read(source, test)
      unstitched_chunks = Ven::Compiler.compile(quotes, context: c_context)
      stitched_chunks = Ven::Optimizer.optimize(unstitched_chunks)
      puts Ven::Machine.run(stitched_chunks, context: m_context)
    end

    puts "SUCCESS #{test}".colorize.green, "- TOOK #{took.total_microseconds}us"
  rescue e : Ven::Suite::ReadError
    puts "FAILURE #{e.message}: l. #{e.line}, f. #{e.file}".colorize.red
  rescue e : Ven::Suite::CompileError
    puts "FAILURE #{e.message}: #{e.traces}".colorize.red
  rescue e : Ven::Suite::RuntimeError
    puts "FAILURE #{e.message}: #{e.traces}".colorize.red
  end
end

# Should work if the Inquirer server is running on port 3000.
orchestra = Ven::Orchestra.new

program = <<-EOF
  expose std;

  ensure not true?(false);
  ensure starts-with?("hello", `he`);
  ensure empty?([]);
EOF

orchestra.from(program)
