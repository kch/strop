#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/strop"

class TestOpt < Minitest::Test
  include Strop::Exports

  def test_optdecl_creation
    opt = Optdecl[:f]
    assert_equal ["f"], opt.names
    assert_equal :shant, opt.arg          # no arg allowed
    assert_equal "f", opt.label

    opt = Optdecl[:f?]                    # ? suffix means optional arg
    assert_equal ["f"], opt.names
    assert_equal :may, opt.arg

    opt = Optdecl[:f!]                    # ! suffix means required arg
    assert_equal ["f"], opt.names
    assert_equal :must, opt.arg

    opt = Optdecl[:f, :foo]
    assert_equal ["f", "foo"], opt.names
    assert_equal "foo", opt.label         # label is first long name or first name

    opt = Optdecl[:a, :b, :c]             # multiple short names
    assert_equal ["a", "b", "c"], opt.names
    assert_equal "a", opt.label           # first name when no long names

    opt = Optdecl[:foo_bar]               # symbol underscores become dashes
    assert_equal ["foo-bar"], opt.names
    assert_equal "foo-bar", opt.label

    opt = Optdecl["foo_bar"]              # strings keep underscores
    assert_equal ["foo_bar"], opt.names
  end

  def test_optdecl_predicates
    flag = Optdecl[:f]
    refute flag.arg?                      # doesn't accept arg
    refute flag.arg!                      # doesn't require arg
    refute flag.no?                       # not a --[no-]flag pair

    may_arg = Optdecl[:f?]
    assert may_arg.arg?                   # accepts arg
    refute may_arg.arg!                   # but doesn't require it

    must_arg = Optdecl[:f!]
    assert must_arg.arg?                  # accepts arg
    assert must_arg.arg!                  # and requires it
  end

  def test_optdecl_to_s
    assert_equal "-f", Optdecl[:f].to_s
    assert_equal "-f [X]", Optdecl[:f?].to_s      # [X] indicates optional arg
    assert_equal "-f X", Optdecl[:f!].to_s        # X indicates required arg
    assert_equal "-f, --foo", Optdecl[:f, :foo].to_s
    assert_equal "-f, --foo?", Optdecl[:f, :foo?].to_s  # ?/! only on first name
  end

  def test_optlist_lookup
    optlist = Optlist[Optdecl[:f, :flag], Optdecl[:v, :verbose], Optdecl[:"dry-run"], Optdecl[:user_name]]
    assert_equal "flag", optlist["f"].label      # lookup by short name (string)
    assert_equal "flag", optlist["flag"].label   # lookup by long name (string)
    assert_equal "flag", optlist[:f].label       # lookup by short name (symbol)
    assert_equal "flag", optlist[:flag].label    # lookup by long name (symbol)
    assert_equal "verbose", optlist["v"].label   # lookup by non-label name
    assert_equal "verbose", optlist[:verbose].label # lookup by label name
    assert_equal "verbose", optlist["ver"].label # partial match
    assert_nil optlist["nonexistent"]            # returns nil for unknown opts

    # Test dash option lookups
    dry_decl = optlist[:"dry-run"]
    assert dry_decl
    assert_equal "dry-run", dry_decl.label

    # Test snake_case symbol conversion
    user_decl = optlist[:user_name]              # snake_case lookup
    assert user_decl
    assert_equal "user-name", user_decl.label

    user_decl2 = optlist[:"user-name"]           # dash lookup
    assert_equal user_decl, user_decl2
  end

  def test_short_options
    optlist = Optlist[Optdecl[:f], Optdecl[:v?]]

    res = Strop.parse(optlist, ["-f"])
    assert_equal 1, res.opts.size
    assert_equal "f", res.opts[0].label
    assert_nil res.opts[0].value

    res = Strop.parse(optlist, ["-v", "value"])
    assert_equal 1, res.opts.size
    assert_equal "v", res.opts[0].label
    assert_equal "value", res.opts[0].value

    res = Strop.parse(optlist, ["-v1"])              # -v1 = -v 1 (simplest clumping)
    assert_equal 1, res.opts.size
    assert_equal "v", res.opts[0].label
    assert_equal "1", res.opts[0].value

    res = Strop.parse(optlist, ["--f"])              # --f works same as -f
    assert_equal 1, res.opts.size
    assert_equal "f", res.opts[0].label
    assert_nil res.opts[0].value
  end

  def test_short_option_clumping
    optlist = Optlist[Optdecl[:a], Optdecl[:b], Optdecl[:c!], Optdecl[:v]]

    res = Strop.parse(optlist, ["-ab"])     # -ab = -a -b
    assert_equal 2, res.opts.size
    assert_equal "a", res.opts[0].label
    assert_equal "b", res.opts[1].label

    res = Strop.parse(optlist, ["-abc", "value"])  # -abc value = -a -b -c value
    assert_equal 3, res.opts.size
    assert_equal "c", res.opts[2].label
    assert_equal "value", res.opts[2].value

    res = Strop.parse(optlist, ["-abcvalue"])      # -abcvalue = -a -b -cvalue
    assert_equal 3, res.opts.size
    assert_equal "c", res.opts[2].label
    assert_equal "value", res.opts[2].value

    res = Strop.parse(optlist, ["-cab"])           # -cab = -c=ab (arg-taking opt first)
    assert_equal 1, res.opts.size
    assert_equal "c", res.opts[0].label
    assert_equal "ab", res.opts[0].value

    res = Strop.parse(optlist, ["-aabcd"])         # -aabcd = -a -a -b -c=d (repeated options)
    assert_equal 4, res.opts.size
    assert_equal "a", res.opts[0].label           # first -a
    assert_equal "a", res.opts[1].label           # second -a (not collpased with previous)
    assert_equal "b", res.opts[2].label           # -b flag
    assert_equal "c", res.opts[3].label           # -c with value
    assert_equal "d", res.opts[3].value

    res = Strop.parse(optlist, ["-c", "1", "-c", "2", "-c", "3"])  # repeated options with values
    assert_equal 3, res.opts.size
    assert_equal "c", res.opts[0].label
    assert_equal "1", res.opts[0].value
    assert_equal "c", res.opts[1].label
    assert_equal "2", res.opts[1].value
    assert_equal "c", res.opts[2].label
    assert_equal "3", res.opts[2].value

    res = Strop.parse(optlist, ["-vvv"])               # -vvv = -v -v -v (verbosity case)
    assert_equal 3, res.opts.size
    assert_equal "v", res.opts[0].label               # first -v
    assert_equal "v", res.opts[1].label               # second -v
    assert_equal "v", res.opts[2].label               # third -v
    res.opts.each { |opt| assert_nil opt.value }      # all flags have no value
  end

  def test_long_options
    optlist = Optlist[Optdecl[:verbose?], Optdecl[:version], Optdecl[:amend], Optdecl[:output!]]

    res = Strop.parse(optlist, ["--verbose"])       # optional arg, none given
    assert_equal 1, res.opts.size
    assert_equal "verbose", res.opts[0].label
    assert_nil res.opts[0].value

    res = Strop.parse(optlist, ["--verbose=high"])  # attached value with =
    assert_equal 1, res.opts.size
    assert_equal "high", res.opts[0].value

    res = Strop.parse(optlist, ["--output", "file.txt"])  # separate value
    assert_equal 1, res.opts.size
    assert_equal "file.txt", res.opts[0].value

    # partial matching
    res = Strop.parse(optlist, ["--am"])  # partial match works
    assert_equal 1, res.opts.size
    assert_equal "amend", res.opts[0].label

    # single char doesn't partial match
    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["--a"]) }
    assert_match(/Unknown option: --a/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["-a"]) }
    assert_match(/Unknown option: -a/, err.message)

    # ambiguous partial matches
    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["--ver"]) }
    assert_match(/Unknown option: --ver/, err.message)
  end

  def test_empty_value_handling
    optlist = Optlist[Optdecl[:output?]]

    res = Strop.parse(optlist, ["--output="])    # empty attached value
    opt = res.opts[0]
    assert_equal "", opt.value                   # results in empty string, not nil

    res = Strop.parse(optlist, ["--output", ""]) # empty detached value
    opt = res.opts[0]
    assert_equal "", opt.value                   # also empty string
  end

  def test_separator_handling
    optlist = Optlist[Optdecl[:f]]

    res = Strop.parse(optlist, ["-f", "--", "-not-an-option"])  # -- ends option parsing
    assert_equal 1, res.opts.size
    assert_equal 1, res.args.size
    assert_equal "-not-an-option", res.args[0].value           # treated as positional arg
    assert_equal ["-not-an-option"], res.rest.map(&:value)     # .rest = args after --
  end

  def test_positional_args
    optlist = Optlist[Optdecl[:f]]

    res = Strop.parse(optlist, ["-f", "arg1", "arg2"])
    assert_equal 1, res.opts.size
    assert_equal 2, res.args.size
    assert_equal "arg1", res.args[0].value
    assert_equal "arg2", res.args[1].value

    # dash should parse as positional arg
    res = Strop.parse(optlist, ["-"])
    assert_equal 0, res.opts.size
    assert_equal 1, res.args.size
    assert_equal "-", res.args[0].value
  end

  def test_mixed_args_and_options
    optlist = Optlist[Optdecl[:f], Optdecl[:v?]]

    res = Strop.parse(optlist, ["arg1", "-f", "arg2", "-v", "value", "arg3"])  # intermixed
    assert_equal 2, res.opts.size
    assert_equal 3, res.args.size                       # all positional args
    opts_by_label = res.opts.group_by(&:label)
    assert opts_by_label["f"]
    assert_equal "value", opts_by_label["v"][0].value
    assert_equal ["arg1", "arg2", "arg3"], res.args.map(&:value)

    # dash with options
    res = Strop.parse(optlist, ["-", "-f"])
    assert_equal 1, res.opts.size
    assert_equal 1, res.args.size
    assert_equal "-", res.args[0].value
    assert res.opts[0].label == "f"
  end

  def test_error_handling
    optlist = Optlist[Optdecl[:f], Optdecl[:req!]]

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["--unknown"]) }    # unknown long opt
    assert_match(/Unknown option: --unknown/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["-z"]) }           # unknown short opt
    assert_match(/Unknown option: -z/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["--f=value"]) }    # flag with attached value
    assert_match(/takes no argument/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["--req"]) }        # required arg missing
    assert_match(/Expected argument for option --req/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["-req"]) }         # -req parses as -r, which doesn't exist
    assert_match(/Unknown option: -r/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["---"]) }          # malformed triple dash
    assert_match(/Unknown option: ---/, err.message)

    err = assert_raises(Strop::OptionError) { Strop.parse(optlist, ["--="]) }          # malformed equals only
    assert_match(/Unknown option: --/, err.message)
  end

  def test_opt_data_structure
    optdecl = Optdecl[:v?, :verbose]
    opt = Opt[optdecl, "v", "high"]

    assert_equal optdecl, opt.decl        # reference to original optdecl
    assert_equal "v", opt.name            # name used in invocation (short form)
    assert_equal "high", opt.value        # argument value
    assert_equal "verbose", opt.label     # canonical name for matching (long form)
    refute opt.no?                        # not a --no-flag variant
    assert opt.yes?                       # positive form used

    # Test no-flag behavior
    no_optdecl = Optdecl["quiet", "no-quiet"]
    no_opt = Opt[no_optdecl, "no-quiet"]
    assert_equal "no-quiet", no_opt.name  # name used in invocation (negative form)
    assert_equal "quiet", no_opt.label    # canonical name is still positive
    assert no_opt.no?                     # detected as --no-flag variant
    refute no_opt.yes?                    # not positive form
  end

  def test_arg_data_structure
    arg = Arg["value"]
    assert_equal "value", arg.value
    assert_equal "value", arg.arg          # .arg is alias for pattern matching
    assert_equal "value", arg.to_s         # .to_s is alias for .value
  end

  def test_result_accessors
    optlist = Optlist[Optdecl[:f, :flag], Optdecl[:v?, :verbose], Optdecl[:q, :quiet]]
    res = Strop.parse(optlist, ["-f", "-v", "high", "-q", "arg1", "--", "arg2"])

    # Test array access
    assert_equal res[0], res.opts[0]

    # Test opts/args/rest distinction
    assert_equal 3, res.opts.size
    assert_equal 2, res.args.size          # .args = all positional args
    assert_equal ["arg2"], res.rest.map(&:value)  # .rest = only after --

    # Test lookup by different names
    f_opt = res["f"]                       # lookup by short name
    assert_equal "flag", f_opt.label       # label is long name

    f_opt2 = res["flag"]                   # lookup by label name
    assert_equal f_opt, f_opt2             # should be same option

    v_opt = res["v"]                       # lookup by non-label name
    assert_equal "verbose", v_opt.label    # label differs from lookup name
    assert_equal "high", v_opt.value

    v_opt2 = res[:verbose]                 # lookup by label name (symbol)
    assert_equal v_opt, v_opt2             # should be same option

    quiet_opt = res[:q]
    assert quiet_opt
    assert_equal "quiet", quiet_opt.label

    # Test array lookup for all matching options
    all_f_opts = res[["f"]]                # lookup all by short name
    assert_equal 1, all_f_opts.size
    assert_equal f_opt, all_f_opts[0]

    all_flag_opts = res[["flag"]]          # lookup all by label name
    assert_equal 1, all_flag_opts.size
    assert_equal f_opt, all_flag_opts[0]

    all_v_opts = res[["v"]]                # lookup all by short name
    assert_equal 1, all_v_opts.size
    assert_equal v_opt, all_v_opts[0]

    # Test symbol lookups
    v_opt3 = res[:"verbose"]               # symbol lookup
    assert_equal v_opt, v_opt3

    all_v_opts2 = res[[:verbose]]          # array symbol lookup
    assert_equal 1, all_v_opts2.size
    assert_equal v_opt, all_v_opts2[0]
  end

  def test_result_array_lookup_multiple
    optlist = Optlist[Optdecl[:v?, :verbose]]
    res = Strop.parse(optlist, ["-v", "low", "-v", "high", "--verbose", "max"])

    # Single lookup returns first
    first_v = res["v"]
    assert_equal "low", first_v.value

    # Array lookup returns all
    all_v = res[["v"]]
    assert_equal 3, all_v.size
    assert_equal ["low", "high", "max"], all_v.map(&:value)

    all_verbose = res[["verbose"]]
    assert_equal 3, all_verbose.size
    assert_equal all_v, all_verbose

    # Test symbol lookups
    first_v_sym = res[:v]
    assert_equal first_v, first_v_sym

    all_v_sym = res[[:v]]
    assert_equal all_v, all_v_sym

    all_verbose_sym = res[[:verbose]]
    assert_equal all_verbose, all_verbose_sym
  end

  def test_result_dash_underscore_symbols
    optlist = Optlist[Optdecl[:"dry-run"], Optdecl[:user_name]]
    res = Strop.parse(optlist, ["--dry-run", "--user-name", "test"])

    # Test dash options with quoted symbols
    dry_run_opt = res[:"dry-run"]
    assert dry_run_opt
    assert_equal "dry-run", dry_run_opt.label

    all_dry_run = res[[:"dry-run"]]
    assert_equal 1, all_dry_run.size
    assert_equal dry_run_opt, all_dry_run[0]

    # Test underscore symbols converting to dash
    user_opt = res[:user_name]            # snake_case symbol
    assert user_opt
    assert_equal "user-name", user_opt.label

    user_opt2 = res[:"user-name"]         # dash symbol
    assert_equal user_opt, user_opt2

    all_user = res[[:user_name]]          # array with snake_case
    assert_equal 1, all_user.size
    assert_equal user_opt, all_user[0]

    all_user2 = res[[:"user-name"]]       # array with dash
    assert_equal all_user, all_user2
  end

  def test_parse_help_basic
    help = <<~HELP
      Usage: prog [options]

        -f, --flag              Flag option
        -v, --verbose LEVEL     Verbose level
        -o, --output [FILE]     Output file
    HELP

    optlist = Strop.parse_help(help)
    assert_equal 3, optlist.size

    f_opt = optlist["f"]                     # flag option: no args
    assert_equal ["f", "flag"], f_opt.names
    assert_equal :shant, f_opt.arg

    v_opt = optlist["verbose"]               # required arg: LEVEL (no brackets)
    assert_equal ["v", "verbose"], v_opt.names
    assert_equal :must, v_opt.arg

    o_opt = optlist["output"]                # optional arg: [FILE] (in brackets)
    assert_equal ["o", "output"], o_opt.names
    assert_equal :may, o_opt.arg
  end

  def test_optlist_from_help
    help = <<~HELP
      Usage: prog [options]

        -h, --help              Show help
        -v, --verbose LEVEL     Verbose level
        -o, --output [FILE]     Output file
    HELP

    optlist = Optlist.from_help(help)        # alias for Strop.parse_help
    assert_equal 3, optlist.size
    assert_kind_of Optlist, optlist
  end

  def test_parse_help_syntax_variations
    help = <<~HELP
      Options:
        -f,--file[=PATH]        File with optional attached arg
        -i [VAL],--input[=VAL]  Arg on both short and long forms
        -j, --output[=FILE]     Spaces around comma
        -k VAL,--key            Arg only on short form
        -l,--limit VAL          Arg only on long form
    HELP

    optlist = Strop.parse_help(help)
    assert_equal 5, optlist.size

    file_opt = optlist["file"]               # -f,--file[=PATH] (no spaces around comma)
    assert_equal ["f", "file"], file_opt.names
    assert_equal :may, file_opt.arg          # [=PATH] means optional

    input_opt = optlist["input"]             # -i [VAL],--input[=VAL] (arg on both forms)
    assert_equal ["i", "input"], input_opt.names
    assert_equal :may, input_opt.arg         # both [VAL] and [=VAL] are optional

    output_opt = optlist["output"]           # -j, --output[=FILE] (spaces around comma)
    assert_equal ["j", "output"], output_opt.names
    assert_equal :may, output_opt.arg        # [=FILE] means optional

    key_opt = optlist["key"]                 # -k VAL,--key (arg only on short form)
    assert_equal ["k", "key"], key_opt.names
    assert_equal :must, key_opt.arg          # VAL (no brackets) means required

    limit_opt = optlist["limit"]             # -l,--limit VAL (arg only on long form)
    assert_equal ["l", "limit"], limit_opt.names
    assert_equal :must, limit_opt.arg        # VAL (no brackets) means required
  end

  def test_parse_help_no_flags
    help = <<~HELP
      Options:
        --[no-]quiet            Quiet mode
        --[no]force             Force mode
    HELP

    optlist = Strop.parse_help(help)
    assert_equal 2, optlist.size

    quiet_opt = optlist["quiet"]             # --[no-]quiet expands to both forms
    assert_equal ["quiet", "no-quiet"], quiet_opt.names
    assert quiet_opt.no?                     # detected as no-flag pair

    force_opt = optlist["force"]             # --[no]force expands to --force/--noforce
    assert_equal ["force", "noforce"], force_opt.names
    assert force_opt.no?                     # detected as no-flag pair
  end

  def test_parse_help_attached_args
    help = <<~HELP
      Options:
        --color=MODE            Color mode
        --debug[=LEVEL]         Debug level
    HELP

    optlist = Strop.parse_help(help)
    assert_equal 2, optlist.size

    color_opt = optlist["color"]             # --color=MODE requires arg (no brackets)
    assert_equal :must, color_opt.arg

    debug_opt = optlist["debug"]             # --debug[=LEVEL] optional arg (brackets)
    assert_equal :may, debug_opt.arg
  end

  def test_parse_help_warning_cases
    # Capture stderr to test warning output
    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      help = <<~HELP
        Options:
          --file  PATH
          --quiet Suppresses output
      HELP

      optlist = Strop.parse_help(help)
      assert_equal 2, optlist.size

      file_opt = optlist["file"]           # PATH seen as description, --file is flag
      assert_equal :shant, file_opt.arg

      quiet_opt = optlist["quiet"]         # Suppresses interpreted as arg
      assert_equal :must, quiet_opt.arg

      # Check warning was printed for the ambiguous case
      assert_match(/interpreted as argument/, $stderr.string)
      assert_match(/Suppresses/, $stderr.string)
    ensure
      $stderr = original_stderr
    end
  end

  def test_no_flag_parsing
    optlist = Optlist[Optdecl["quiet", "no-quiet"]]  # manual no-flag setup

    res = Strop.parse(optlist, ["--quiet"])
    opt = res.opts[0]
    assert_equal "quiet", opt.name         # name used in invocation
    refute opt.no?                         # positive form
    assert opt.yes?

    res = Strop.parse(optlist, ["--no-quiet"])
    opt = res.opts[0]
    assert_equal "no-quiet", opt.name      # negative form used
    assert opt.no?                         # detected as negated
    refute opt.yes?
  end

  def test_comprehensive_parsing_scenarios
    optlist = Optlist[
      Optdecl[:d], Optdecl[:e], Optdecl[:a],
      Optdecl[:b?], Optdecl[:c!], Optdecl[:opt?], Optdecl[:req!]
    ]

    # [argv, expected_opts_as_strings, expected_rest_args]
    test_cases = [
      [[], [], []],                                            # empty
      [%w[--], [], []],                                        # just separator
      [%w[-- --], [], %w[--]],                                 # -- becomes arg after --
      [%w[-a], %w[a], []],                                     # simple flag
      [%w[-a --], %w[a], []],                                  # flag then separator
      [%w[-a b -- -z], %w[a], %w[-z]],                         # mixed with separator
      [%w[-b val], %w[b=val], []],                             # optional arg taken
      [%w[-c val], %w[c=val], []],                             # required arg
      [%w[--opt=foo], %w[opt=foo], []],                        # attached long arg
      [%w[--req=bar], %w[req=bar], []],                        # attached required
      [%w[-cabd], %w[c=abd], []],                              # short clump with value
      [%w[--opt=--foo], %w[opt=--foo], []],                    # value with -- prefix
      [%w[--req=--foo=bar], %w[req=--foo=bar], []],            # value with -- and =
      [%w[--opt=foo=bar], %w[opt=foo=bar], []],                # value with = inside
      [%w[-a -b -- pos], %w[a b], %w[pos]],                    # multiple opts
    ]

    test_cases.each do |argv, expected_opts, expected_args|
      res = Strop.parse(optlist, argv)
      actual_opts = res.opts.map { |o| [o.name, o.value].compact.join("=") }
      actual_args = res.rest.map(&:value)               # only args after --

      assert_equal expected_opts, actual_opts, "Options mismatch for #{argv.inspect}"
      assert_equal expected_args, actual_args, "Args mismatch for #{argv.inspect}"
    end
  end

  def test_edge_cases
    optlist = Optlist[Optdecl[:f], Optdecl[:v?]]

    # Empty argv
    res = Strop.parse(optlist, [])
    assert_empty res.opts
    assert_empty res.args

    # Only separator
    res = Strop.parse(optlist, ["--"])
    assert_empty res.opts
    assert_empty res.args

    # Option-like args after separator (treated as regular args)
    res = Strop.parse(optlist, ["--", "-f", "--verbose"])
    assert_empty res.opts
    assert_equal 2, res.args.size
    assert_equal ["-f", "--verbose"], res.args.map(&:value)
  end

  def test_parse_from_io
    help_text = "  -f, --flag  Flag option\n"

    # Create temporary file for IO test (parse() accepts IO objects)
    require "tempfile"
    Tempfile.create("help") do |file|
      file.write(help_text)
      file.rewind

      res = Strop.parse(file, [])          # parses help from IO, then argv
      assert_equal 0, res.size             # empty argv = no results
    end

    # Test parsing help from string directly
    optlist = Strop.parse_help(help_text)
    assert_equal 1, optlist.size
    assert_equal "flag", optlist[0].label
  end

  def test_parse_defaults_to_argv
    optlist = Optlist[Optdecl[:f]]

    # Save original ARGV and replace it
    original_argv = ARGV.dup
    ARGV.replace(["-f", "arg"])

    begin
      res = Strop.parse(optlist)           # no argv argument = uses ARGV
      assert_equal 1, res.opts.size
      assert_equal "f", res.opts[0].label
      assert_equal 1, res.args.size
      assert_equal "arg", res.args[0].value
    ensure
      ARGV.replace(original_argv)          # restore original ARGV
    end
  end

  def test_pattern_matching_support
    optlist = Optlist[Optdecl[:help], Optdecl[:verbose?], Optdecl["color", "no-color"]]
    res = Strop.parse(optlist, ["--help", "--verbose", "high", "--no-color", "arg"])

    help_opt = nil
    verbose_opt = nil
    color_opt = nil
    args = []

    res.each do |item|                     # demonstrate pattern matching
      case item
      in Opt[label: "help"] then help_opt = item                    # match by label
      in Opt[label: "verbose", value:] then verbose_opt = [item, value]  # capture value
      in Opt[label: "color"] then color_opt = item                  # no-flags work too
      in Arg[value:] then args << value                             # match args
      end
    end

    assert help_opt
    assert_equal "help", help_opt.label
    assert verbose_opt
    assert_equal "high", verbose_opt[1]    # captured value
    assert color_opt
    assert color_opt.no?                   # --no-color detected
    assert_equal ["arg"], args

    # Test compact pattern matching style
    help_found = false
    files = []

    res.each do |item|
      case item
      in label: "help" then help_found = true              # only Opt has .label
      in arg:          then files << arg                   # Arg offers .arg alias
      else # ignore other opts like verbose, color
      end
    end

    assert help_found
    assert_equal ["arg"], files
  end

  def test_parse_error_handling_with_parse_bang
    optlist = Optlist[Optdecl[:f]]

    # Capture stderr to test error output (parse! prints and exits)
    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      assert_raises(SystemExit) { Strop.parse!(optlist, ["--unknown"]) }
      assert_match(/Unknown option/, $stderr.string)  # error message printed
    ensure
      $stderr = original_stderr
    end
  end

  def test_duplicate_options_in_help
    help = <<~HELP
      Options:
        -f, --flag     First flag
        -f             Second flag (duplicate)
    HELP

    assert_raises(RuntimeError) { Strop.parse_help(help) }  # detects duplicates
  end

  def test_conflicting_arg_requirements
    help = <<~HELP
      Options:
        -f ARG, --flag [ARG]    Conflicting requirements
    HELP

    assert_raises(RuntimeError) { Strop.parse_help(help) }  # required vs optional conflict
  end

  def test_custom_padding_in_help
    help = <<~HELP
      Options:
      \t-f, --flag\tFlag with tabs
    HELP

    optlist = Strop.parse_help(help, pad: /\t/)  # custom indentation pattern
    assert_equal 1, optlist.size
    assert_equal "flag", optlist[0].label
  end

  def test_optlist_case_generation
    optlist = Optlist[Optdecl[:help], Optdecl[:verbose?], Optdecl["quiet", "no-quiet"]]
    case_output = optlist.to_s(:case)        # generates pattern matching template

    assert_kind_of String, case_output
    assert case_output.include?('label: "help"')           # flag option pattern
    assert case_output.include?('label: "verbose", value:') # value-taking option pattern
    assert case_output.include?('opt.no?')                 # no-flag detection pattern
  end



  def test_special_characters_in_args
    optlist = Optlist[Optdecl[:msg!]]

    res = Strop.parse(optlist, ["--msg=--foo=bar"])  # value looks like option with =
    opt = res.opts[0]
    assert_equal "--foo=bar", opt.value             # parser doesn't get confused

    res = Strop.parse(optlist, ["--msg=hello world"]) # value with spaces
    opt = res.opts[0]
    assert_equal "hello world", opt.value             # spaces preserved in value
  end

  def test_question_mark_and_bang_in_option_names
    opt1 = Optdecl[:help?, arg: :shant]        # explicit arg overrides ? modifier
    assert_equal ["help?"], opt1.names
    assert_equal :shant, opt1.arg

    opt2 = Optdecl[:debug!, arg: :shant]       # explicit arg overrides ! modifier
    assert_equal ["debug!"], opt2.names
    assert_equal :shant, opt2.arg

    opt3 = Optdecl[:"?", arg: :shant]          # literal ? option name
    assert_equal ["?"], opt3.names
    assert_equal :shant, opt3.arg

    opt4 = Optdecl["foo!", arg: :shant]        # only explicit arg: keeps ! literal
    assert_equal ["foo!"], opt4.names
    assert_equal :shant, opt4.arg

    opt5 = Optdecl["foo!"]                     # string names also strip ! without arg:
    assert_equal ["foo"], opt5.names
    assert_equal :must, opt5.arg
  end



  def test_comprehensive_help_parsing
    help = <<~HELP
      Usage: myapp [OPTIONS] files...

      Options:
        -h, --help              Show help
        -v, --verbose           Verbose output
        -q, --quiet             Quiet mode
        -f, --file FILE         Input file
        -o, --output [FILE]     Output file (optional)
        --color[=MODE]          Color mode
        --config=FILE           Config file
        -n, --dry-run           Don't actually do anything
        --[no-]timestamps       Include timestamps
        --[no]backup            Create backup

      Examples:
        myapp -v --file input.txt
        myapp --no-timestamps *.rb
    HELP

    optlist = Strop.parse_help(help)
    assert_equal 10, optlist.size

    # Check various option types
    help_opt = optlist["help"]
    assert_equal :shant, help_opt.arg

    file_opt = optlist["file"]
    assert_equal :must, file_opt.arg

    output_opt = optlist["output"]
    assert_equal :may, output_opt.arg

    color_opt = optlist["color"]
    assert_equal :may, color_opt.arg

    config_opt = optlist["config"]
    assert_equal :must, config_opt.arg

    timestamps_opt = optlist["timestamps"]
    assert timestamps_opt.no?
    assert_equal ["timestamps", "no-timestamps"], timestamps_opt.names

    backup_opt = optlist["backup"]
    assert backup_opt.no?
    assert_equal ["backup", "nobackup"], backup_opt.names
  end
  def test_parse_help_complex_text
    help = <<~HELP
      Usage: myapp [OPTIONS] input.txt
             myapp --version

      A tool for processing files with various options.

      Options:
        -h, --help              Show this help message and exit.
                                See the man page for detailed info.
        -v, --verbose           Enable verbose output. Can be used multiple
                                times to increase verbosity level.
        -o, --output FILE       Specify output file. If not provided,
                                results go to stdout by default.

      Examples:
        myapp -v input.txt
        myapp --output=result.txt input.txt

      Report bugs to: bugs@example.com
    HELP

    optlist = Strop.parse_help(help)
    assert_equal 3, optlist.size

    help_opt = optlist["help"]
    assert_equal ["h", "help"], help_opt.names
    assert_equal :shant, help_opt.arg

    verbose_opt = optlist["verbose"]
    assert_equal ["v", "verbose"], verbose_opt.names
    assert_equal :shant, verbose_opt.arg

    output_opt = optlist["output"]
    assert_equal ["o", "output"], output_opt.names
    assert_equal :must, output_opt.arg
  end

  def test_mixed_string_symbol_names
    opt = Optdecl[:f, "flag", :verbose]   # mixed string/symbol names
    assert_equal ["f", "flag", "verbose"], opt.names  # string stays, symbol converts
    assert_equal "flag", opt.label        # first name with length > 1
  end

  def test_sep_constant_behavior
    optlist = Optlist[Optdecl[:f]]
    res = Strop.parse(optlist, ["-f", "--", "arg"])

    assert_equal 3, res.size
    assert_kind_of Opt, res[0]
    assert_equal Sep, res[1]              # Sep constant works
    assert_kind_of Arg, res[2]
  end
end
