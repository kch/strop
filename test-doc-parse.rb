#!/usr/bin/env ruby

require_relative "opt"

puts "call me with --help or try --bar / --no-bar" if ARGV.empty?

help = DATA.read
optspec = Optspec.from_help help
# puts optspec.to_s
opts = parse!(ARGV, optspec)
# y opts

for opt in opts
  case opt
  in Opt[label: "help"] then puts help
  in Opt[label: "bar", name: "no-bar"]  then puts "nobar!"
  in Opt[label: "bar"]  then puts puts "yes-bar"
  else puts "???"
  end
end



__END__
Usage lol

opts:
  --help
  --flag1
  --flag2 [arg]
  --flag3 arg
  --flag4=arg
  -f,--flag5[=arg]
  --[no]foo
  --[no-]bar
  -g
  -h 123
  -i [123],--fl[=123]
  -j, --fl[=123]
  # -a,-b,--foo=1,--bar,-c
--

  # -R BAR, --foo[=BAR]   this must fail

  -r,-R,--foo[=BAR]
  -r,-R,--foo [BAR] <- determ if mandatory from here too
  -R [BAR], --foo[=BAR]
  -r BAR,--foo BAR doc
                   long doc
  -r,--[no]rrr <arg>
  -r,--[no-]rrr

Optspec customizations:
- auto --no- opt, add --foo if see --no-foo
- any flag, return a magic optdef, letting any flag true

keep -- in resutls? like in git separate args from paths etc
