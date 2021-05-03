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
puts "exposes (should be: std, a.b.c, d.e.f): #{reader.exposes?.map(&.join(".")).join(", ")}"

quotes = reader.read

puts Ven::Suite::Detree.detree(quotes)

# Reader.read


tests =
  Dir["examples/*.ven"] +
  Dir["test/**/*.ven"] +
  Dir["std/**/*.ven"]

tests.each do |test|
  source = File.read(test)

  begin
    took = Time.measure do
      Ven::Reader.read(source, test)
    end

    puts "SUCCESS #{test}".colorize.green, "- TOOK #{took.total_microseconds}us"
  rescue e : Ven::Suite::ReadError
    puts "FAILURE #{e.message}: l. #{e.line}, f. #{e.file}".colorize.red
  end
end
