#!/usr/bin/env ruby

require_relative "opt"
require "yaml"
require "psych/y"

HELP = <<HELP.gsub("PROG", File.basename($0))
Usage PROG

opts:
  -h,--help
  --flag1
  --flag2 [arg]
  --flag3 arg
  --flag4=arg
  -f,--flag5[=arg]
  --noggins
  --[no]foo
  --[no-]bar
  -g
  -i [123],--fl[=123]
  -j, --flx[=123]
HELP


puts "call me with --help or try --bar / --no-bar" if ARGV.empty?


include TipTopt
optspec = Optspec.from_help HELP
# puts optspec.to_s
res = TipTopt::parse!(ARGV, optspec)
o,a,rest = res.opts, res.args, res.rest
y res
y o
y a
y rest

for opt in res
  case opt
  in Opt[label: "help"] then puts HELP
  in Opt[label: "bar"]  then puts opt.no? ? "NObar" : "YESbar"
  in Opt[label: "noggins"] then puts "nog #{opt.no?}" # should be false
  else puts "???"
  end
end
