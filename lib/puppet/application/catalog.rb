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
    $catalog_file = arg
  end

  def main
    unless catalog = Puppet::Resource::Catalog.indirection.find(Puppet[:certname])
      raise "Could not find catalog for #{Puppet[:certname]}"
    end
      compiled_catalog_pson_string = catalog.to_pson

      paths = catalog.vertices.
        select {|vertex| vertex.type == "File"}.
        map {|file_resource| Puppet::FileServing::Metadata.find(file_resource[:source])}. # this step should return nil where source doesn't exist
        compact.
        map {|filemetadata| filemetadata.path}

    pp paths
    pp catalog if options[:debug]
  end
end
