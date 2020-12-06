require "fancyline"

require "./ven/*"

fancy = Fancyline.new

unless ARGV.empty?
  source = File.read(ARGV.first)
  # before_tree = Time.monotonic
  tree = Ven::Parser.from(ARGV.first, source)
  # after_tree = Time.monotonic
  # tree.map { |x| puts x }
  # puts "reading took #{(after_tree - before_tree).microseconds}qs"
  begin
    Ven::Machine.from(tree, Ven::Context.new)
  rescue e : Ven::RuntimeError
    puts "runtime error: #{e.message}"
  end
else
  scope = Ven::Context.new
  scope.define("true", Ven::MBool.new(true))
  scope.define("false", Ven::MBool.new(false))
  puts "Note that you can prefix a line with .e<times>",
       "to evaluate this line <times> times and get",
       "*arithmetic mean* of the execution time"
  while source = fancy.readline("> ")
    begin
      unless source.empty?
        repeat = 1
        do_print = true
        if source =~ /\.e(\d+)(.*)/
          repeat = $1.to_i
          source = $2
        elsif source =~ /\.\!(.*)/
          do_print = false
          source = $1
        end
        tree = Ven::Parser.from("<interactive>", source)
        stats = [] of Int32
        code = [] of Ven::Model
        repeat.times do
          before_exec = Time.monotonic
          code = Ven::Machine.from(tree, scope)
          after_exec = Time.monotonic
          stats << (after_exec - before_exec).microseconds
        end
        puts code.last if do_print && !code.empty?
        puts "{ran in mean (_ / #{repeat}): #{stats.sum / stats.size}qs}"
      end
    rescue e : Ven::InternalError
      puts "internal error: #{e.message}"
    rescue e : Ven::ParseError
      puts "parse error (#{e.file}:#{e.line}, near '#{e.char}'): #{e.message}"
    rescue e : Ven::RuntimeError
      puts "runtime error: #{e.message}"
    end
  end
end
