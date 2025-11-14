# Command-line Option Parser

## Distinctive features

- Build options from parsing help text, instead of the other way around
- Pattern matching for result processing (with `case`/`in …`)

## Core workflow

```ruby
opts = Optlist.from_help(help_text)  # extract from help
result = Strop.parse(opts, ARGV)     # parse argv -> Result
result = Strop.parse!(opts, ARGV)    # same but on error prints message and exits
result = Strop.parse!(help_text)     # Automatically parse help text, ARGV default
```

## Processing parsed results

```ruby
Strop.parse!(help).each do |item|
  case item
  in Strop::Opt[label: "help"]               then show_help
  in Strop::Opt[label: "verbose", value:]    then set_verbose(value)
  in Strop::Opt[label: "output", value: nil] then output = :stdout
  in Strop::Opt[label: "color"]              then item.no? ? disable_color : enable_color
  in Strop::Arg[value:]                      then files << value
  in Strop::Sep                              then break
  end
end
```

Or, more succinctly:

```ruby
Strop.parse!(help).each do |item|
  case item
  in label: "help" then show_help     # only Opt has .label
  in arg:          then files << arg  # `value:` might match an Opt, so Arg offters alias .arg
  end
end
```

You can generate the case expression above with:

```ruby
puts Strop::Optlist.from_help(help_text).to_s(:case)
```


## Result members (Array of Opt, Arg, Sep)

```ruby
res.opts                             # all Opt objects
res.args                             # all Arg objects
res.rest                             # args after -- separator
res["flag"]                          # find opt by name

opt = res.opts.first
arg = res.args.first
opt.decl                             # Optdecl matched for this Opt instance
opt.name                             # name used in invocation (could differ from label)
opt.value                            # argument passed to this option
opt.label                            # primary name (first long name or first name), used for pattern matching
opt.no?                              # true if --no-foo variant used
opt.yes?                             # opposite of `no?`
arg.value                            # positional argument
arg.arg                              # same as .value, useful for pattern matching
Sep                                  # -- end of options marker; Const, not instantiated
```

Notice that parsing `--[no-]flag` from help results in a single `Optdecl[:flag, :"no-flag"]`, and you can use `yes?`/`no?` to check which was passed.


## Help text format for parsing

Auto-extracts indented option lines from help:

```
Options:
  -f, --flag              Flag
  -v, --verbose LEVEL     Required arg
  -o, --output [FILE]     Optional arg
  --color=MODE            Optional with =
  --debug[=LEVEL]         Required/optional with =
  --[no-]quiet            --quiet/--no-quiet pair
  --[no]force             --force/--noforce pair
```

By default `parse_help` expects options to be indented by 2 or 4 spaces. Override with:

```ruby
Strop.parse_help(text, pad: / {6}/)  # 6 spaces exactly
Strop.parse_help(text, pad: /\t/)    # tabs ????
```

Use at least two spaces before description, and only a single space before args.

```
  --file  PATH                       # !! PATH seen as description and ignored, --file considered a flag (no arg)
  --quiet Suppresses output          # !! interpreted as --quiet=Suppresses
```

The latter case is detected and a warning is printed, but best to avoid this situation altogether.

## Command-line parsing features

```bash
cmd -abc                              # short option clumping (-a -b -c)
cmd -fVAL, --foo=VAL                  # attached values
cmd -f VAL, --foo VAL                 # separate values
cmd --foo val -- --bar                # --bar becomes positional after --
cmd --intermixed args and --options   # flexible ordering
```

## Manual option declaration building

```ruby
Optdecl[:f]                           # flag only: -f
Optdecl[:f?]                          # optional arg: -f [X]
Optdecl[:f!]                          # required arg: -f x
Optdecl[:f, :foo]                     # multiple names: -f or --foo
Optdecl[:f?, :foo]                    # multiple + arg modifier: use ?/! only on first
Optdecl[:f?, :foo?]                   # so this will result in -f, --foo?
Optdecl[:f, :foo, arg: :may]          # explicit arg form: --foo [ARG]
Optdecl[:?, arg: :shant]              # explicit form allows using ?/! in option name: -?
Optdecl[:foo_bar]                     # --foo-bar: Underscores in symbol names get replaced with `-`
Optdecl["foo_bar"]                    # --foo_bar: but not in strings.
```

### Option lists:

```ruby
optlist = Optlist[optdecl1, optdecl2] # combine decls into optlist
optlist["f"]                          # lookup by name
```

## Argument requirements

- `:shant` - no argument allowed
- `:may`   - optional argument (takes next token if not option-like)
- `:must`  - required argument (error if missing)

## Adding hidden options

If you want to use `parse_help` mainly, but need secret options:

```ruby
optlist = Strop.parse_help HELP
optlist << Optdecl[:D, :debug]
```
