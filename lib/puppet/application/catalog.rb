require 'pp'
require 'puppet/application'

class Puppet::Application::Catalog < Puppet::Application

  should_parse_config
  #run_mode :agent

  option("--debug","-d")
  option("--verbose","-v")

  option("--list RESOURCE", "-l") do |arg|
    @res = arg
  end

  option("--catalog CATALOG", "-c") do |arg|

  def main
    unless catalog = Puppet::Resource::Catalog.indirection.find(Puppet[:certname])
      raise "Could not find catalog for #{Puppet[:certname]}"
    end

    pp catalog
  end
end
