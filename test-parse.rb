#!/usr/bin/env ruby

require_relative "opt"
require "yaml"
require "psych/y"

include TipTopt::Exports

optlist = Optlist[
  Optdecl[:d],
  Optdecl[:e],
  Optdecl[:a],
  Optdecl[:b?],
  Optdecl[:c!],
  Optdecl[:not],
  Optdecl[:opt?],
  Optdecl[:req!],
  Optdecl[:foo_bar],
  Optdecl["foo_bar"],
]

tests = [
  [%w[],                               %w[], %w[]],
  [%w[ -- ],                           %w[], %w[]],
  [%w[ -- -- ],                        %w[], %w[ -- ]],
  [%w[ -- a ],                         %w[], %w[ a ]],
  [%w[ a -- b ],                       %w[], %w[ a b ]],
  [%w[ a -- -z -w -- ],                %w[], %w[ a -z -w -- ]],
  [%w[ -a ],                           %w[ a ], %w[]],
  [%w[ -a -- -z -w ],                  %w[ a ], %w[ -z -w ]],
  [%w[ -a b -- -z -w ],                %w[ a ], %w[ b -z -w ]],
  [%w[ -a b c w z ],                   %w[ a ], %w[ b c w z ]],
  [%w[ -a b c d -- z ],                %w[ a ], %w[ b c d z ]],
  [%w[ -a -- ],                        %w[ a ], %w[]],
  [%w[ --a ],                          %w[ a ], %w[]],
  [%w[ --b=1 ],                        %w[ b=1 ], %w[]],
  [%w[ -a -b c -- z ],                 %w[ a b=c ], %w[ z ]],
  [%w[ -a -b -- z ],                   %w[ a b ], %w[ z ]],
  [%w[ -aabcd --req=foo -- z ],        %w[ a a b=cd req=foo ], %w[ z ]],
  [%w[ --opt --not ],                  %w[ opt not ], %w[]],
  [%w[ --opt ],                        %w[ opt ], %w[]],
  [%w[ --req= ],                       %w[ req= ], %w[]],
  [%w[ --opt=foo=bar ],                %w[ opt=foo=bar ], %w[]],
  [%w[ -cabd --opt=--foo -- z ],       %w[ c=abd opt=--foo ], %w[ z ]],
  [%w[ --req=--foo=bar ],              %w[ req=--foo=bar ], %w[ ]],
  [%w[ -a --not nop --opt --req foo z ], %w[ a not opt req=foo ], %w[ nop z ]],
  ].map {|a,b,c| [a, b.map{ it.split(?=, 2) },c] }
  .each do |argv, ropts, rargs|
    puts "check: " + argv.inspect
    opts, args = TipTopt.parse(argv, optlist).group_by{it.class}.tap{it.default=[]}.values_at(Opt, Arg)
    rargs == args.map{it.value} or raise
    ropts == opts.map{ [it.name, it.value].compact } or raise
  end

fails = %w[ --err  ---  --=  --not=1  -a1  --a=1 -z -az -c --req ]
fails.each do |argv|
  TipTopt.parse([argv], optlist)
  raise "Should fail: #{argv}"
rescue TipTopt::OptionError
end


# exit

test = tests.sample[0]
parsed = TipTopt.parse!(test, optlist)
p test
y parsed
puts "=="
parsed.each do |opt|
  case opt
  in Opt[label: "c"]   then puts opt.value.upcase
  in Opt[label: "req"] then puts opt.value+" IS REQ"
  in Opt[value: nil]   then puts "#{opt.label}!"
  in Opt               then puts "#{opt.label}=#{opt.value}"
  in Arg               then p opt.value
  else puts "??"
  end
end
