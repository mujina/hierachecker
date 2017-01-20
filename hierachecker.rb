#!/usr/bin/env ruby 

###############################################################################
#                                                                             #
#  Copyright 2017 Pugme Ltd                                                   #
#                                                                             # 
#  Licensed under the Apache License, Version 2.0 (the "License");            #
#  you may not use this file except in compliance with the License.           #
#  You may obtain a copy of the License at                                    #
#                                                                             #  
#    http://www.apache.org/licenses/LICENSE-2.0                               #
#                                                                             #
#  Unless required by applicable law or agreed to in writing, software        #
#  distributed under the License is distributed on an "AS IS" BASIS,          #
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
#  See the License for the specific language governing permissions and        #
#  limitations under the License.                                             #
#                                                                             #
###############################################################################

require 'hiera'
require 'yaml'
require 'optparse'
require 'ostruct'
require 'json'
require 'colorize'

# https://groups.google.com/forum/#!topic/puppet-users/yuOCsLTsvDQ

# Override module method to remove console logging
class Hiera
  module Console_logger
    class << self 
      alias_method :debug_quiet, :debug 
      
      def debug(msg)
        debug_quiet(msg)
      end

      def debug_quiet(msg) 
        # Print nothing 
      end
    end
  end
end

class HieraCheckerParser

  def self.parse(args)

    options = OpenStruct.new
    options.verbose = false
    options.help = false
    program = File.basename($0)

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{ program } [options]"

      opts.on("-e", "--environment [ENVIRONMENT]", "Puppet environment") do |e|
        options.environment = e
      end

      opts.on("--hierayaml [HIERAYAML]", "Hiera YAML file") do |hy|
        options.hiera_yaml = hy
      end

      opts.on("--key [KEY]", "Key") do |k|
        options.key = k
      end

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options.verbose = v
      end

      opts.on("-h", "--help", "This help") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    options
  end

end

class HieraChecker 

  HIERA_YAML_DEFAULT = '/etc/puppetlabs/puppet/hiera.yaml'
  ENVIRONMENT_DEFAULT = 'production'
  # Cannot use ::trusted.certname for key here as Hash does not support dot 
  # in key name. Ostruct or HashDot should sort this out. TODO
  CLIENTCERT_KEY = 'clientcert' 
  TESTS_PATH = 'tests'

  attr_reader :environment

  # http://www.rubydoc.info/gems/hiera/Hiera#initialize-instance_method
  def initialize(options = {})  
    @options = options

    @failures = Array.new
    @successes = Array.new
    
    @environment = options[:environment] || ENVIRONMENT_DEFAULT
    @verbose     = options[:verbose]                                  

    self.parse_config()

    @hiera_yaml  = options[:hiera_yaml]  || @config['hiera_yaml']     || HIERA_YAML_DEFAULT
    @debug       =                          @config['debug']          || false
    @tests_path  =                          @config['tests_path']     || TESTS_PATH
    @clientcert_key =                       @config['clientcert_key'] || CLIENTCERT_KEY

    self.load_global_facts()

    @hiera_options = Hash.new(0)
    @hiera_options[:config] = @hiera_yaml
    @hiera = Hiera.new(@hiera_options)


    puts "Environment = #{ @environment }".yellow if @verbose
  end


  def parse_config() 
    @config = JSON.parse(File.read("config.json"))
  end

  def load_global_facts()
    global_facts = {}
    begin
      @global_facts = YAML.load_file("facts.yaml") 
    rescue Errno::ENOENT => e
      puts "No global facts found".yellow if @verbose
    end
  end

  def make_facts(h) 
    return {} if h.nil?
    h.map {|k, v| ["::#{ k }", v] }.to_h 
  end

  def add_facts(facts_h, scope)
    self.make_facts(facts_h).each_pair do |f,v| 
      puts "Adding fact #{ f } = #{ v }".blue if @debug
      scope[f] = v
    end
  end

  def merge_facts(facts_h, scope) 
    scope.merge!(self.make_facts(facts_h))
  end

  def get_version() 
    puts Hiera::version
  end

  def lookup(key, scope, assert) 
    #http://www.rubydoc.info/gems/hiera/3.2.0/Hiera
    puts "Searching #{ key } with scope #{ scope.to_s }".blue if @debug
    puts "Searching #{ key }".yellow if @yellow

    hiera_value = @hiera.lookup(key, nil, scope)

    info = (scope.key?(@clientcert_key) ?
      "#{ scope['::role'] }:#{ scope['clientcert'] }" : scope['::role']) + ":#{ key }"

    if hiera_value.nil?
      puts "[#{ info }] #{ key } not found in Hiera".red
      @failures.push(info)
      return
    end

    if !compare(hiera_value, assert)
      puts "[#{ info }] #{ key } assertion failed".red
      puts "#{ hiera_value } does not match #{ assert }".red
      @failures.push(info)
    else 
      puts "[#{ info }] #{ key } assertion passed".green
      @successes.push(info)
    end
  end 

  def get_config_files()
    Dir.glob(@tests_path + '/**/*.yaml')
  end

  def compare(v1,v2) 
    # First are the types identical
    return false if !v1.class.eql?(v2.class)

    # Turns out you can compare String, Array & Hash with eql?
    return false if !v1.eql?(v2) 

    return true
  end

  def run_lookups(key = nil)
    self.get_config_files.each do |f|  

      role = File.basename(f).split('.')[0]
      puts "Loading test file #{f}".yellow if @verbose

      yaml = YAML.load_file(f)
      yaml.each do |k,v|

        next if !key.nil? && !key.eql?(k)

        scope = Hash.new(0)

        self.add_facts(@global_facts, scope)

        scope['environment'] = @environment
        scope['::role']      = role

        if v.key?("facts") 
          self.merge_facts(v['facts'], scope)
        end

        if v.key?('clientcert') 
          v['clientcert'].keys.each do |c| 

            client_scope = scope.clone

            client_scope[@clientcert_key] = c

            if v['clientcert'][c].key?('facts') && 
               self.merge_facts(v['clientcert'][c]['facts'], client_scope)
            end

            hiera_value = self.lookup(k,client_scope,v['clientcert'][c]['assert'])
          end
        end 
        if v['assert'] 
          hiera_value = self.lookup(k,scope,v['assert'])
        end
      end
    end
  end

  def run_report() 
    puts "---------------------------------------------------------------------"
    puts "Run complete for environment #{ @environment }:" 

    puts "\t - Successful lookups".green
    @successes.each do |k| 
       puts "\t\t - #{ k }".green
    end

    puts "\t - Failed lookups".red
    @failures.each do |k| 
       puts "\t\t - #{ k }".red
    end

    puts "Summary:"
    puts "\t - Success #{ @successes.length }".green
    puts "\t - Failure #{ @failures.length }".red

    puts "Copyright \u00A9 Pugme Ltd. All rights reserved."
  end
end

options = HieraCheckerParser.parse(ARGV)

hc = HieraChecker.new(options.to_h)

hc.run_lookups(options[:key])
hc.run_report()
