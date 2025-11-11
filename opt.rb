#!/usr/bin/env ruby

require "yaml"
require "psych/y"

Optdef = Data.define(:labels, :arg) do
  def initialize(labels:, arg: nil)
    labels = [*labels]
    labels[0] = labels[0].to_s.sub(/[!?]$/, "").to_sym unless arg
    arg ||= { ?? => :may, ?! => :must }[$&] || :shant
    %i[must may shant].include? arg or raise "invalid arg"
    super labels:, arg:
  end

  def arg? = self.arg != :shant
  def arg! = self.arg == :must
end

Arg = Data.define :value do
  def encode_with(coder) = (coder.scalar = self.value; coder.tag = nil)
end

Opt = Data.define :spec, :key, :value do
  def initialize(spec:, key:, value: nil) = super(spec:, key:, value:)
  def label = spec.labels.find{ it.size > 1 } || spec.labels.first
  def deconstruct_keys(...) = to_h.merge(label: label)
  def encode_with(coder) = (coder.map = { self.key => self.value }; coder.tag = nil)
end

class Unreachable < RuntimeError; end

class Optspec < Array
  def [](k) = self.find{ it.labels.include? k.to_sym }
end


def parse(argv, optspec)
  tokens = argv.dup
  args = []
  ctx = :top
  flag, token, opt = nil
  rx_value = /\A[^-]|\A\z/
  loop do
    case ctx
    when :end then break args += tokens.map{ Arg[it] }  # opt parsing ended, rest is positional args
    when :value then ctx = :top; args << Arg[token]     # interspersed positional arg amidst opts

    when :top
      token = tokens.shift or next ctx = :end                                   # next token or done
      case token
      when "--"              then ctx = :end                                    # end of options
      when /\A-([^-].*)\z/m  then token, ctx = $1, :short                       # short or clump (-a, -abc)
      when /\A--([^-].+)\z/m then token, ctx = $1, :long                        # long (--foo, --foo xxx), long with attached value (--foo=xxx)
      when rx_value          then ctx = :value                                  # value
      else raise Unreachable
      end

    when :short
      flag, token = token[0], token[1..].then{ it != "" ? it : nil }            # -abc -> a, bc
      opt = optspec[flag] or raise "Unknown option: -#{flag}"
      case
      when  opt.arg? &&  token then ctx = :top; args << Opt[opt, flag, token]   # -aXXX
      when !opt.arg? && !token then ctx = :top; args << Opt[opt, flag]          # end of -abc
      when  opt.arg? && !token then ctx = :arg                                  # -a XXX
      when !opt.arg? &&  token then args << Opt[opt, flag]                      # -abc -> took -a, will parse -bc
      else raise Unreachable
      end

    when :long
      flag, value = token =~ /\A(.*?)=/m ? [$1, $'] : [token, nil]
      opt = optspec[flag] or raise "Unknown option: --#{flag}"
      case
      when  opt.arg? &&  value then ctx = :top; args << Opt[opt, flag, value]   # --foo=XXX
      when !opt.arg? && !value then ctx = :top; args << Opt[opt, flag]          # --foo
      when  opt.arg? && !value then ctx = :arg                                  # --foo XXX
      when !opt.arg? &&  value then raise "Option --#{flag} takes no argmument"
      else raise Unreachable
      end

    when :arg
      token = tokens[0]&.=~(rx_value) ? tokens.shift : nil
      case
      when opt.arg! && !token then raise "Expected argument for option -#{?- if flag[1]}#{flag}" # --req missing value; (!peek implied)
      when opt.arg! &&  token then ctx = :top; args << Opt[opt, flag, token]    # --req val
      when opt.arg? &&  token then ctx = :top; args << Opt[opt, flag, token]    # --opt val
      when opt.arg? && !token then ctx = :top; args << Opt[opt, flag]           # --opt followed by --foo, --opt as last token
      else raise Unreachable
      end

    else raise Unreachable
    end
  end
end

optspec = Optspec[
  Optdef.new(:d),
  Optdef.new(:e),
  Optdef.new(:a),
  Optdef.new(:b?),
  Optdef.new(:c!),
  Optdef.new(:not),
  Optdef.new(:opt?),
  Optdef.new(:req!),
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
  [%w[ -a -b c -- z ],                 %w[ a b=c ], %w[ z ]],
  [%w[ -a -b -- z ],                   %w[ a b ], %w[ z ]],
  [%w[ -aabcd --req=foo -- z ],        %w[ a a b=cd req=foo ], %w[ z ]],
  [%w[ --opt --not ],                  %w[ opt not ], %w[]],
  [%w[ --opt ],                        %w[ opt ], %w[]],
  [%w[ --opt=foo=bar ],                %w[ opt=foo=bar ], %w[]],
  [%w[ -cabd --opt=--foo -- z ],       %w[ c=abd opt=--foo ], %w[ z ]],
  [%w[ -a --not nop --opt --req foo z ], %w[ a not opt req=foo ], %w[ nop z ]],
  ].map {|a,b,c| [a, b.map{ it.split(?=, 2) },c] }
  .each do |argv, ropts, rargs|
    puts "check: " + argv.inspect
    opts, args = parse(argv, optspec).group_by{it.class}.tap{it.default=[]}.values_at(Opt, Arg)
    rargs == args.map{it.value} or raise
    ropts == opts.map{ [it.key, it.value].compact } or raise
  end

# opts, args = parsed.group_by{it.class}.values_at(Opt, Arg)


exit

test = tests.sample
parsed = parse(test, optspec)
p test
y parsed
puts "=="
parsed.each do |opt|
  case opt
  in Opt[label: :c]   then puts opt.value.upcase
  in Opt[label: :opt] then puts opt.value
  in Opt              then puts "#{opt.label}=#{opt.value}"
  in Arg              then p opt.value
  else puts "??"
  end
end


__END__
expect
--flag
--flag [arg]
--flag arg
--flag=arg
-fgh
-f123
-fgh23
-f 123
-f [123]
words
--


-r,-R,--foo[=BAR]
-r,-R,--foo [BAR] <- determ if mandatory from here too
-R [BAR], --foo[=BAR]
-r BAR,--foo BAR
-r,-[no]rrr
-r,-[no-]rrr


Optspec customizations:
- auto --no- opt, add --foo if see --no-foo
- any flag, return a magic optdef, letting any flag true

keep -- in resutls? like in git separate args from paths etc
