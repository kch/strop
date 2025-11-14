#!/usr/bin/env ruby

# Command-line option parser
#
# Core workflow:
#   opts = Optlist.from_help(help_text)  # extract from help
#   args = parse(opts, ARGV)             # parse argv -> Result
#   args = parse!(opts, ARGV)            # exits on error
#
# Manual option declaration building:
#   Optdecl[:f]                           # flag only: -f
#   Optdecl[:f?]                          # optional arg: -f [X]
#   Optdecl[:f!]                          # required arg: -f x
#   Optdecl[[:f, :foo]]                   # multiple names: -f or --foo
#   Optdecl[names: [:f, :foo], arg: :may] # explicit arg form
#
#   Single char opts: short flag -f, otherwise --flag
#
#   Use explicit form if you want to use ?/! in option name:
#   Optdecl[:?, arg: :shant]              # allows -? option
#
#   Strings are accepted too. Underscores in symbol names get
#   replaced with -, but not in strings.
#
#   Optdecl["foo_bar"] # --foo_bar
#   Optdecl[:foo_bar]  # --foo-bar
#
#   optlist = Optlist[optdecl1, optdecl2] # combine opt list
#   optlist["f"]                          # lookup by name
#
# Argument requirements:
#   :shant - no argument allowed
#   :may   - optional argument (takes next token if not option-like)
#   :must  - required argument (error if missing)
#
# Parse results: Result (Array of Opt, Arg, Sep)
#   res.opts                             # all Opt objects
#   res.args                             # all Arg objects
#   res.rest                             # args after -- separator
#
#   Opt.decl                             # matched Optdecl
#   Opt.name                             # matched name ("f" or "foo")
#   Opt.value                            # "bar" or nil
#   Opt.label                            # primary display name
#   Opt.no?                              # true if --no-foo variant used
#   Arg.value                            # positional argument
#   Sep                                  # -- separator marker
#
#   label is the first long name or first name if no long found
#   label can be used for matching results as below:
#
# Processing parsed results:
#   res.each do |item|
#     case item
#     in Opt[label: "help"]                    then show_help
#     in Opt[label: "verbose", value:]         then set_verbose(value)
#     in Opt[label: "output", value: nil]      then output = :stdout
#     in Opt[label: "color"]                   then opt.no? ? disable_color : enable_color
#     in Arg[value:]                           then files << value
#     in Sep                                   then break
#     end
#   end
#
# Help text format for parsing (auto-extracts indented option lines):
#   -f, --foo                            # flag
#   -f, --foo X                          # required arg
#   -f, --foo [X]                        # optional arg
#   --foo=X, --foo [=X]                  # required/optional with =
#   --[no-]foo, --[no]foo                # --foo/--nofoo pair
#
#   --[no-]foo and --[no]foo are both supported by parse_help.
#
# Command-line parsing features:
#   -abc                                 # short option clumping (-a -b -c)
#   -fVAL, --foo=VAL                     # attached values
#   -f VAL, --foo VAL                    # separate values
#   --foo val -- --bar                   # --bar becomes positional after --
#   intermixed args and options          # flexible ordering


# require "yaml"
# require "psych/y"
# require "debug"
# DEBUGGER__.add_catch_breakpoint "Exception"

module Strop

  Optdecl = Data.define(:names, :arg, :label) do
    def initialize(names:, arg: nil)
      names = [*names].map{ Symbol === it ? it.to_s.gsub(?_, ?-) : it }
      names[0] = names[0].sub(/[!?]$/, "") unless arg
      arg ||= { ?? => :may, ?! => :must }[$&] || :shant
      label = names.find{ it.size > 1 } || names.first # the canonical name
      %i[must may shant].member? arg or raise "invalid arg"
      super names:, arg:, label:
    end

    def no?  = names.each_cons(2).any?{|a,b| b =~ /\Ano-?#{Regexp.escape a}\z/ }
    def arg? = self.arg != :shant
    def arg! = self.arg == :must
    def to_s = names.map{ (it[1] ? "--" : "-")<<it }.join(", ") + { must: " X", may: " [X]", shant: "" }[arg]
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
          for opt in Strop.parse!(optlist)
            case opt
            #{caseins.map{ "  #{it}" }.join("\n").lstrip}
            case Arg[value:] then
            case Sep then break # if you want to handle result.rest separately
            else raise "Unhandled result #{opt}"
            end
          end
        RUBY
      end
    end
  end


  Arg = Data.define :value do
    def encode_with(coder) = (coder.scalar = self.value; coder.tag = nil)
  end

  Opt = Data.define :decl, :name, :value, :label, :no do
    def initialize(decl:, name:, value: nil)
      label = decl.label # repeated here so can be pattern-matched against
      no = name =~ /\Ano-?/ && decl.names.member?($')
      super(decl:, name:, value:, label:, no: !!no)
    end
    alias no? no
    def encode_with(coder) = (coder.map = { self.name => self.value }; coder.tag = nil)
  end

  Sep = :end_marker

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
    when String  then parse_help(optlist)
    when Optlist then optlist
    else raise "optlist must be an Optlist or help text (given #{optlist.class})"
    end
    tokens = argv.dup
    res = Result.new
    ctx = :top
    flag, token, opt = nil
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
        flag, value = token =~ /\A(.*?)=/m ? [$1, $'] : [token, nil]
        opt = optlist[flag] or raise OptionError, "Unknown option: --#{flag}"
        case
        when  opt.arg? &&  value then ctx = :top; res << Opt[opt, flag, value]    # --foo=XXX
        when !opt.arg? && !value then ctx = :top; res << Opt[opt, flag]           # --foo
        when  opt.arg? && !value then ctx = :arg                                  # --foo XXX
        when !opt.arg? &&  value then raise OptionError, "Option --#{flag} takes no argument"
        else raise Unreachable
        end

      when :short
        flag, token = token[0], token[1..].then{ it != "" ? it : nil }            # -abc -> a, bc
        opt = optlist[flag] or raise OptionError, "Unknown option: -#{flag}"
        case
        when  opt.arg? &&  token then ctx = :top; res << Opt[opt, flag, token]    # -aXXX
        when !opt.arg? && !token then ctx = :top; res << Opt[opt, flag]           # end of -abc
        when  opt.arg? && !token then ctx = :arg                                  # -a XXX
        when !opt.arg? &&  token then res << Opt[opt, flag]                       # -abc -> took -a, will parse -bc
        else raise Unreachable
        end

      when :arg
        token = tokens[0]&.=~(rx_value) ? tokens.shift : nil
        case
        when opt.arg! && !token then raise OptionError, "Expected argument for option -#{?- if flag[1]}#{flag}" # --req missing value; (!peek implied)
        when opt.arg! &&  token then ctx = :top; res << Opt[opt, flag, token]     # --req val
        when opt.arg? &&  token then ctx = :top; res << Opt[opt, flag, token]     # --opt val
        when opt.arg? && !token then ctx = :top; res << Opt[opt, flag]            # --opt followed by --foo, --opt as last token
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


  RX_SOARG = /\[\S+?\]/
  RX_SARG  = /[^\s,]+/
  RX_LOARG = /\[=\S+?\]| #{RX_SOARG}/
  RX_LARG  = /[ =]#{RX_SARG}/
  RX_NO    = /\[no-?\]/
  RX_SOPT  = /-[^-\s,](?: (?:#{RX_SOARG}|#{RX_SARG}))?/
  RX_LOPT  = /--(?=[^-=,\s])#{RX_NO}?[^\s=,\[]+(?:#{RX_LOARG}|#{RX_LARG})?/
  RX_OPT   = /#{RX_SOPT}|#{RX_LOPT}/
  RX_OPTS  = /#{RX_OPT}(?:, {0,2}#{RX_OPT})*/

  def self.parse_help(help, pad: /(?:  ){1,2}/)
    help.scan(/^#{pad}#{RX_OPTS}/).map do |line| # get all opts
      line.scan(RX_OPT).map do |opt|    # take each line
        opt.split(/(?=\[=)|=| +/, 2)    # separate flag from arg
      end.map do |flag, arg|            # remove flag markers -/--, transform arg str into requirement
        [flag.sub(/^--?/, ''), arg.nil? ? :shant : arg[0] == "[" ? :may : :must]
      end.transpose           # [[flag,arg], ...] -> [flags, args]
      .then do |flags, args|  # hanfle -f,--foo=x style, without arg on short flag, and expand --[no]flag into --flag and --noflag (also --[no-])
        args = args.uniq.tap{ it.delete :shant if it.size > 1 }                            # delete excess :shant (from -f in -f,--foo=x)
        raise "flag #{flags} has conflicting arg requirements: #{args}" if args.size > 1   # raise if still conflict, like -f X, --ff [X]
        [(flags.flat_map{|f| f.start_with?(RX_NO) ? [$', $&[1...-1] + $'] : f }).uniq, args[0]] # [flags and noflags, resolved single arg]
      end
    end.uniq.tap do |list| # [[[flag, flag, ...], arg, more opts ...]
      dupes = list.flat_map(&:first).tally.reject{|k,v|v==1}
      raise "Flags #{dupes.keys.inspect} seen more than once in distinct definitions" if dupes.any?
    end.map{ Optdecl[*it] }.then{ Optlist[*it] }
  end


end
