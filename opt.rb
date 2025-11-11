#!/usr/bin/env ruby

require "yaml"
require "psych/y"

Optdef = Data.define(:names, :arg) do
  def initialize(names:, arg: nil)
    names = [*names].map(&:to_sym)
    names[0] = names[0].to_s.sub(/[!?]$/, "").to_sym unless arg
    arg ||= { ?? => :may, ?! => :must }[$&] || :shant
    %i[must may shant].include? arg or raise "invalid arg"
    super names:, arg:
  end

  def arg? = self.arg != :shant
  def arg! = self.arg == :must
end

class Optspec < Array # a list of Optdefs
  def [](k) = self.find{ it.names.include? k.to_sym }
end


Arg = Data.define :value do
  def encode_with(coder) = (coder.scalar = self.value; coder.tag = nil)
end

Opt = Data.define :optdef, :name, :value, :label do
  def initialize(optdef:, name:, value: nil)
    label = optdef.names.find{ it.size > 1 } || optdef.names.first # the primary name we use to refer to it
    super(optdef:, name:, value:, label:)
  end
  def encode_with(coder) = (coder.map = { self.name => self.value }; coder.tag = nil)
end

class Unreachable < RuntimeError; end
class OptionError < ArgumentError; end

def parse(argv, optspec)
  Array === argv && argv.all?{ String === it } or raise "argv must be an array of strings (given #{argv.class})"
  Optspec === optspec or raise "optspec must be an Optspec (given #{optspec.class})"
  tokens = argv.dup
  args = []
  ctx = :top
  flag, token, opt = nil
  rx_value = /\A[^-]|\A\z/
  loop do
    case ctx
    when :end then return args += tokens.map{ Arg[it] }  # opt parsing ended, rest is positional args
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
      opt = optspec[flag] or raise OptionError, "Unknown option: -#{flag}"
      case
      when  opt.arg? &&  token then ctx = :top; args << Opt[opt, flag, token]   # -aXXX
      when !opt.arg? && !token then ctx = :top; args << Opt[opt, flag]          # end of -abc
      when  opt.arg? && !token then ctx = :arg                                  # -a XXX
      when !opt.arg? &&  token then args << Opt[opt, flag]                      # -abc -> took -a, will parse -bc
      else raise Unreachable
      end

    when :long
      flag, value = token =~ /\A(.*?)=/m ? [$1, $'] : [token, nil]
      opt = optspec[flag] or raise OptionError, "Unknown option: --#{flag}"
      case
      when  opt.arg? &&  value then ctx = :top; args << Opt[opt, flag, value]   # --foo=XXX
      when !opt.arg? && !value then ctx = :top; args << Opt[opt, flag]          # --foo
      when  opt.arg? && !value then ctx = :arg                                  # --foo XXX
      when !opt.arg? &&  value then raise OptionError, "Option --#{flag} takes no argument"
      else raise Unreachable
      end

    when :arg
      token = tokens[0]&.=~(rx_value) ? tokens.shift : nil
      case
      when opt.arg! && !token then raise OptionError, "Expected argument for option -#{?- if flag[1]}#{flag}" # --req missing value; (!peek implied)
      when opt.arg! &&  token then ctx = :top; args << Opt[opt, flag, token]    # --req val
      when opt.arg? &&  token then ctx = :top; args << Opt[opt, flag, token]    # --opt val
      when opt.arg? && !token then ctx = :top; args << Opt[opt, flag]           # --opt followed by --foo, --opt as last token
      else raise Unreachable
      end

    else raise Unreachable
    end
  end
end


RX_SOARG = /\[\S+?\]/
RX_SARG  = /[^\s,]+/
RX_LOARG = /\[=\S+?\]| #{RX_SOARG}/
RX_LARG  = /[ =]#{RX_SARG}/
RX_NO    = /\[no-?\]/
RX_SOPT  = /-[^-\s,](?: (?:#{RX_SOARG}|#{RX_SARG}))?/
RX_LOPT  = /--(?=[^-=,\s])#{RX_NO}?[^\s=,\[]+(?:#{RX_LOARG}|#{RX_LARG})?/
RX_OPT   = /#{RX_SOPT}|#{RX_LOPT}/
RX_OPTS  = /#{RX_OPT}(?:, {0,2}#{RX_OPT})*/

def doc_parse(help, pad: /(?:  ){1,2}/)
  help.scan(/^#{pad}#{RX_OPTS}/).map{|line|    # get all opts
    line.scan(RX_OPT).map{|opt|    # take each line
      opt.split(/(?=\[=)|=| +/, 2) # separate flag from arg
    }.map{|flag, arg|              # remove flag markers -/--, transform arg str into requirement
      [flag.sub(/^--?/, ''), arg.nil? ? :shant : arg[0] == "[" ? :may : :must]
    }.transpose                    # [[flag,arg],...]] -> [flags, args]
    .then{|flags, args|  # hanfle -f,--foo=x style, without arg on short flag, and expand --[no]flag into --flag and --noflag (also --[no-])
      args = args.uniq.tap{ it.delete :shant if it.size > 1 }                            # delete excess :shant (from -f in -f,--foo=x)
      raise "flag #{flags} has conflicting arg requirements: #{args}" if args.size > 1   # raise if still conflict, like -f X, --ff [X]
      [(flags.flat_map{|f| f.start_with?(RX_NO) ? [$', $&[1...-1] + $'] : f }), args[0]] # [flags and noflags, resolved single arg]
    }
  }
end


y doc_parse DATA.read

exit


optspec = Optspec[
  Optdef[:d],
  Optdef[:e],
  Optdef[:a],
  Optdef[:b?],
  Optdef[:c!],
  Optdef[:not],
  Optdef[:opt?],
  Optdef[:req!],
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
    ropts == opts.map{ [it.name, it.value].compact } or raise
  end



exit

test = tests.sample[0]
parsed = parse(test, optspec)
p test
y parsed
puts "=="
parsed.each do |opt|
  case opt
  in Opt[label: :c]   then puts opt.value.upcase
  in Opt[label: :req] then puts opt.value+" IS REQ"
  in Opt[value: nil]  then puts "#{opt.label}!"
  in Opt              then puts "#{opt.label}=#{opt.value}"
  in Arg              then p opt.value
  else puts "??"
  end
end




__END__
opts:
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
  -a,-b,--foo=1,--bar,-c
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
