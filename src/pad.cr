require "./lib"

r = Ven::Reader.new(File.read("examples/calculator.ven"))
puts r.read.join("\n")

# # Ways of using the reader:
# #
# # 1) Reading and getting an array of quotes:
# puts Ven::Reader.read("untitled", "1 + 1")
# # 2) Reading and recieving the quotes one after another:
# Ven::Reader.read("untitled", "1 + 1") { |quote| puts quote }
# # 3) Making an instance of Reader and using it:
# reader = Ven::Reader.new("untitled", "1 + 1")
# # 3.1) Reading and getting an array of quotes:
# puts reader.read
# # 3.2) Reading and recieving the quotes one after another:
# # reader.read { |quote| puts quote }
# # 3.3) Retrieving distinct & exposes (only in this order):
# reader2 = Ven::Reader.new("untitled", "distinct a; expose a.b; expose b.c;")
# puts reader2.distinct?
# puts reader2.exposes?

# Reader.read
