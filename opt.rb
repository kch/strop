#!/usr/bin/env ruby

# require "yaml"
# require "psych/y"
# require "debug"
# DEBUGGER__.add_catch_breakpoint "Exception"

module Strop

  Optdecl = Data.define(:names, :arg, :label) do
    def self.[](*names, arg: nil) = new(names:, arg:)
    def initialize(names:, arg: nil)
      names = [*names].map{ Symbol === it ? it.to_s.gsub(?_, ?-) : it } # :foo_bar to "foo-bar" for symbols
      names[0] = names[0].sub(/[!?]$/, "") unless arg                   # opt? / opt! to opt, and... (unless arg given)
      arg ||= { ?? => :may, ?! => :must }[$&] || :shant                 # use ?/! to determine arg (unless arg given)
      label = names.find{ it.size > 1 } || names.first                  # the canonical name used to search for it
      %i[must may shant].member? arg or raise "invalid arg"             # validate arg
      super names:, arg:, label:
    end

    def no?  = names.each_cons(2).any?{|a,b| b =~ /\Ano-?#{Regexp.escape a}\z/ } # is a flag like --[no-]foo, --[no]bar
    def arg? = self.arg != :shant # accepts arg
    def arg! = self.arg == :must  # requires arg
    def to_s = names.map{ (it[1] ? "--" : "-")+it }.join(", ") + { must: " X", may: " [X]", shant: "" }[arg]
  end

  class Optlist < Array # a list of Optdecls
    def self.from_help(doc) = Strop.parse_help(doc)
    def [](k, ...) = [String, Symbol].any?{ it === k } ? self.find{ it.names.member? k.to_s } : super(k, ...)
    def to_s(as=:plain)
      case as
      when :plain then join("\n")
      when :case
        caseins = map{|os| "in label: #{os.label.inspect}".tap{ it << ", value:" if os.arg? }}
        len = caseins.map(&:size).max
        caseins = caseins.zip(self).map{ |s,o| s.ljust(len) + " then#{' opt.no?' if o.no?} # #{o}" }
        puts <<~RUBY
          for item in Strop.parse!(optlist)
            case item
            #{caseins.map{ "  #{it}" }.join("\n").lstrip}
            case Strop::Arg[value:] then
            case Strop::Sep then break # if you want to handle result.rest separately
            else raise "Unhandled result \#{item}"
            end
          end
        RUBY
      end
    end
  end


  Arg = Data.define :value, :arg do
    def initialize(value:) = super(value:, arg: value)
  end

  Opt = Data.define :decl, :name, :value, :label, :no do
    def initialize(decl:, name:, value: nil)
      label = decl.label                              # repeated here so can be pattern-matched against in case/in
      no = name =~ /\Ano-?/ && decl.names.member?($') # flag given in negated version: (given --no-foo and also accepts --foo)
      super(decl:, name:, value:, label:, no: !!no)
    end
    alias no? no
    def yes? = !no?
  end

  Sep = :end_marker

  # for debugging only, TODO remove later probably
  class Arg
    def encode_with(coder) = (coder.scalar = self.value; coder.tag = nil)
  end
  class Opt
    def encode_with(coder) = (coder.map = { self.name => self.value }; coder.tag = nil)
  end


  module Exports
    Optlist = Strop::Optlist
    Optdecl = Strop::Optdecl
    Opt     = Strop::Opt
    Arg     = Strop::Arg
    Sep     = Strop::Sep
  end

  class Result < Array # of Opt, Arg, Sep
    def rest = drop_while{ it != Sep }.drop(1) # args after sep
    def args = Result.new(select { Arg === it })
    def opts = Result.new(select { Opt === it })
    def [](k, ...)
      case k
      when String, Symbol then find{ Opt === it && it.decl.names.member?(k.to_s) }
      else super(k, ...)
      end
    end
  end

  class Unreachable < RuntimeError; end
  class OptionError < ArgumentError; end

  def self.parse(optlist, argv=ARGV)
    Array === argv && argv.all?{ String === it } or raise "argv must be an array of strings (given #{argv.class})"
    optlist = case optlist
    when IO      then parse_help(optlist.read)
    when String  then parse_help(optlist)
    when Optlist then optlist
    else raise "optlist must be an Optlist or help text (given #{optlist.class})"
    end
    tokens = argv.dup
    res = Result.new
    ctx = :top
    name, token, opt = nil
    rx_value = /\A[^-]|\A\z/
    loop do
      case ctx
      when :end then return res.concat tokens.map{ Arg[it] } # opt parsing ended, rest is positional args
      when :value then ctx = :top; res << Arg[token]         # interspersed positional arg amidst opts

      when :top
        token = tokens.shift or next ctx = :end                                   # next token or done
        case token
        when "--"          then ctx = :end; res << Sep                            # end of options
        when /\A--(.+)\z/m then token, ctx = $1, :long                            # long (--foo, --foo xxx), long with attached value (--foo=xxx)
        when /\A-(.+)\z/m  then token, ctx = $1, :short                           # short or clump (-a, -abc)
        when rx_value      then ctx = :value                                      # value
        else raise Unreachable
        end

      when :long
        name, value = token =~ /\A(.*?)=/m ? [$1, $'] : [token, nil]
        opt = optlist[name] or raise OptionError, "Unknown option: --#{name}"
        case
        when  opt.arg? &&  value then ctx = :top; res << Opt[opt, name, value]    # --foo=XXX
        when !opt.arg? && !value then ctx = :top; res << Opt[opt, name]           # --foo
        when  opt.arg? && !value then ctx = :arg                                  # --foo XXX
        when !opt.arg? &&  value then raise OptionError, "Option --#{name} takes no argument"
        else raise Unreachable
        end

      when :short
        name, token = token[0], token[1..].then{ it != "" ? it : nil }            # -abc -> a, bc
        opt = optlist[name] or raise OptionError, "Unknown option: -#{name}"
        case
        when  opt.arg? &&  token then ctx = :top; res << Opt[opt, name, token]    # -aXXX
        when !opt.arg? && !token then ctx = :top; res << Opt[opt, name]           # end of -abc
        when  opt.arg? && !token then ctx = :arg                                  # -a XXX
        when !opt.arg? &&  token then res << Opt[opt, name]                       # -abc -> took -a, will parse -bc
        else raise Unreachable
        end

      when :arg
        token = tokens[0]&.=~(rx_value) ? tokens.shift : nil
        case
        when opt.arg! && !token then raise OptionError, "Expected argument for option -#{?- if name[1]}#{name}" # --req missing value
        when opt.arg! &&  token then ctx = :top; res << Opt[opt, name, token]     # --req val
        when opt.arg? &&  token then ctx = :top; res << Opt[opt, name, token]     # --opt val
        when opt.arg? && !token then ctx = :top; res << Opt[opt, name]            # --opt followed by --foo, --opt as last token
        else raise Unreachable
        end

      else raise Unreachable
      end
    end
  end

  def self.parse!(...) # same but catches errors, print msg, exit
    parse(...)
  rescue OptionError => e
    $stderr.puts e.message
    exit 1
  end


  RX_SOARG = /\[\S+?\]/                        # short opt optional arg
  RX_SARG  = /[^\s,]+/                         # short opt required arg
  RX_LOARG = /\[=\S+?\]| #{RX_SOARG}/          # long opt optional arg: --foo[=bar] or --foo [bar]
  RX_LARG  = /[ =]#{RX_SARG}/                  # long opt required arg: --foo=bar or --foo bar
  RX_NO    = /\[no-?\]/                        # prefix for --[no-]flags
  RX_SOPT  = /-[^-\s,](?: (?:#{RX_SOARG}|#{RX_SARG}))?/                      # full short opt
  RX_LOPT  = /--(?=[^-=,\s])#{RX_NO}?[^\s=,\[]+(?:#{RX_LOARG}|#{RX_LARG})?/  # full long opt
  RX_OPT   = /#{RX_SOPT}|#{RX_LOPT}/           # either opt
  RX_OPTS  = /#{RX_OPT}(?:, {0,2}#{RX_OPT})*/  # list of opts, comma separated

  def self.parse_help(help, pad: /(?:  ){1,2}/)
    help.scan(/^#{pad}(#{RX_OPTS})(.*)/).map do |line, rest| # get all opts lines
      # Ambiguous: --opt Desc with only one space before will interpret "Desc" as arg.
      if rest =~ /^ \S/ && line =~ / (#{RX_SARG})$/ # desc preceeded by sringle space && last arg is " "+word. Capture arg name
        $stderr.puts "#{$1.inspect} was interpreted as argument, In #{(line+rest).inspect}. Use at least two spaces before description to avoid this warning."
      end
      line.scan(RX_OPT).map do |opt|    # take options from each line
        opt.split(/(?=\[=)|=| +/, 2)    # separate name from arg
      end.map do |name, arg|            # remove opt markers -/--, transform arg str into requirement
        [name.sub(/^--?/, ''), arg.nil? ? :shant : arg[0] == "[" ? :may : :must]
      end.transpose           # [[name,arg], ...] -> [names, args]
      .then do |names, args|  # handle -f,--foo=x style (without arg on short opt); expand --[no]flag into --flag and --noflag (also --[no-])
        args = args.uniq.tap{ it.delete :shant if it.size > 1 }                                  # delete excess :shant (from -f in -f,--foo=x)
        raise "Option #{names} has conflicting arg requirements: #{args}" if args.size > 1       # raise if still conflict, like -f X, --ff [X]
        [(names.flat_map{|f| f.start_with?(RX_NO) ? [$', $&[1...-1] + $'] : f }).uniq, args[0]]  # [flags and noflags, resolved single arg]
      end
    end.uniq.tap do |list| # [[[name, name, ...], arg, more opts ...]
      dupes = list.flat_map(&:first).tally.reject{|k,v|v==1}
      raise "Options #{dupes.keys.inspect} seen more than once in distinct definitions" if dupes.any?
    end.map{ |names, arg| Optdecl[*names, arg:] }.then{ Optlist[*it] }
  end


end
