require 'yaml'

# Functions are stored in generated files as both Procs (:function) and 
# Strings (:function_id). The String version makes comparisons of Procs much 
# easier.
#
# TODO:
# - better comparison of existing rules
def parse_holiday_defs(module_name, files)
  regions = []
  rules_by_month = {}
  custom_methods = {}
  test_strs = []

  files.each do |file|
    def_file = YAML.load_file(file)
    puts "  Loading #{file}"
    if def_file['months']
      puts "   - importing dates..."
      def_file['months'].each do |month, definitions|
        rules_by_month[month] = [] unless rules_by_month[month]
        definitions.each do |definition|
          rule = {}
          definition.each do |key, val|
            rule[key] = val
          end

          rule['regions'] = rule['regions'].collect { |r| r.to_sym }

          regions << rule['regions']

          exists = false
          rules_by_month[month].each do |ex|
            if ex['name'] == rule['name'] and ex['wday'] == rule['wday'] and ex['mday'] == rule['mday'] and ex['week'] == rule['week'] and ex['type'] == rule['type'] and ex['function'] == rule['function'] and ex['observed'] == rule['observed']
              ex['regions'] << rule['regions'].flatten
              exists = true
            end
          end
          unless exists
            rules_by_month[month] << rule
          end

        end # /defs.each
      end
    end

    if def_file['methods']
      puts "   - importing methods..."
      def_file['methods'].each do |name, code|
        custom_methods[name] = code
      end # /methods.each
    end

    if def_file['tests']
      puts "   - importing testings..."
      test_strs << def_file['tests']
    end
  end

  # Build the definitions
  month_strs = []
  rules_by_month.each do |month, rules|
    month_str = "      #{month.to_s} => ["
    rule_strings = []
    rules.each do |rule|
      str = '{'
      if rule['mday']
        str << ":mday => #{rule['mday']}, "
      elsif rule['function']
        str << ":function => lambda { |year| Holidays.#{rule['function']} }, "
        str << ":function_id => \"#{rule['function'].to_s}\", "
      else
        str << ":wday => #{rule['wday']}, :week => #{rule['week']}, "
      end

      if rule['observed']
        str << ":observed => lambda { |date| Holidays.#{rule['observed']}(date) }, "
        str << ":observed_id => \"#{rule['observed'].to_s}\", "
      end

      if rule['type']
        str << ":type => :#{rule['type']}, "
      end

      # shouldn't allow the same region twice
      str << ":name => \"#{rule['name']}\", :regions => [:" + rule['regions'].uniq.join(', :') + "]}"
      rule_strings << str
    end
    month_str << rule_strings.join(",\n            ") + "]"
    month_strs << month_str
  end

  month_strs.join(",\n")


  # Build the methods
  method_str = ''
  custom_methods.each do |key, code|
    method_str << code + "\n\n"
  end


  # Build the module file
  module_src =<<-EOM
# coding: utf-8
module Holidays
  # This file is generated by the Ruby Holiday gem.
  #
  # Definitions loaded: #{files.join(', ')}
  #
  # To use the definitions in this file, load them right after you load the 
  # Holiday gem:
  #
  #   require 'holidays'
  #   require 'holidays/#{module_name.downcase}'
  #
  # More definitions are available at http://code.dunae.ca/holidays.
  module #{module_name} # :nodoc:
    DEFINED_REGIONS = [:#{regions.flatten.uniq.join(', :')}]

    HOLIDAYS_BY_MONTH = {
#{month_strs.join(",\n")}
    }
  end

#{method_str}
end

Holidays.merge_defs(Holidays::#{module_name}::DEFINED_REGIONS, Holidays::#{module_name}::HOLIDAYS_BY_MONTH)
EOM


# Build the test file
  unless test_strs.empty?
    test_src =<<-EndOfTests
require File.dirname(__FILE__) + '/../test_helper'

# This file is generated by the Ruby Holiday gem.
#
# Definitions loaded: #{files.join(', ')}
class #{module_name.capitalize}DefinitionTests < Test::Unit::TestCase  # :nodoc:

  def test_#{module_name.downcase}
#{test_strs.join("\n\n")}
  end
end
    EndOfTests
  end

return module_src, test_src || ''

end