#!/usr/bin/ruby
#
# Copyright PuppetLabs 2010

require 'getoptlong'
require 'puppet'
require 'pp'

opts = GetoptLong.new(
  [ '--node',           '-n', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--confdir',        '-c', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--vardir',         '-v', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--modulepath',     '-p', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--external_nodes', '-e', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--manifest',       '-m', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--debug',          '-d', GetoptLong::NO_ARGUMENT ],
  [ '--help',           '-h', GetoptLong::NO_ARGUMENT ]
)

version        = "1.0"
node, external_nodes, modulepath, debug = nil, nil, Puppet[:modulepath], false
opts.each do |opt, arg|
  case opt
    when '--node'
      node = arg
    when '--confdir'
      Puppet[:confdir] = arg
    when '--vardir'
      Puppet[:vardir] =arg
    when '--modulepath'
      Puppet[:modulepath] = arg
    when '--external_nodes'
      external_nodes = arg
    when '--manifest'
      Puppet[:manifest] = arg
    when '--debug'
      debug = true
    when '--help'
      puts "Usage: compile_with_files.rb [-h] [-d] [-p modulepath] [-e ENC_script] [-m manifest file] -n node_certname"
      exit(1)
  end
end

#Puppet[:manifest] = ARGV[0] if defined?ARGV[0]

# tell puppet to get facts from yaml
Puppet::Node::Facts.terminus_class = :yaml

if external_nodes
  # use the external nodes tool - should read from puppet's puppet.conf
  # but doesn't read from the master section because run_mode can't be set.  ticket #4790
  Puppet[:node_terminus] = :exec
  Puppet[:external_nodes] = external_nodes
end

# we're running this on the server but Puppet.run_mode doesn't know that in this script
# so it ends up using clientyamldir
Puppet[:clientyamldir] = Puppet[:yamldir]
begin
  unless compiled_catalog = Puppet::Resource::Catalog.find(node)
    raise "Could not compile catalog for #{node}"
  end
  compiled_catalog_pson_string = compiled_catalog.to_pson

  paths = compiled_catalog.vertices.
      select {|vertex| vertex.type == "File" and vertex[:source] =~ %r{puppet://}}.
      map {|file_resource| Puppet::FileServing::Metadata.find(file_resource[:source])}. # this step should return nil where source doesn't exist
      compact.
      map {|filemetadata| filemetadata.path}

rescue => detail
  $stderr.puts detail
  exit(30)
end

## This was my first attempt to retrieve file paths from the catalog, but requires some parsing of
## the already compiled catalog that I'm not sure is reliable
#compiled_catalog_pson_string = `puppet master --modulepath #{modulepath} --compile #{node}`
## strip notices and warnings http://projects.puppetlabs.com/issues/2527
#compiled_catalog_pson_string = compiled_catalog_pson_string.split("\n").reject {|line| line =~ /warning:|notice:/}
#
#module_files = {}
#compiled_catalog_pson_string.each do |line|
#  module_files[$1] = $2 if line =~ %r{source.*puppet:///modules/(\w+)/(.*)"$}
#end
#
#paths = module_files.map do |module_name, file_name|
#  "#{modulepath}/#{module_name}/files/#{file_name}"
#end
#
#paths = paths.select {|path| File.exist?(path)}
pp paths if debug
pp compiled_catalog_pson_string if debug

catalog_file = File.new("#{node}.catalog.pson", "w")
catalog_file.write compiled_catalog_pson_string
catalog_file.close

File.open("#{node}.modulepath", 'w') {|f| f.write(modulepath)}

tarred_filename = "#{node}.compiled_catalog_with_files.tar.gz"
`tar -cPzf #{tarred_filename} #{catalog_file.path} #{node}.modulepath #{paths.join(' ')}`
puts "Created #{tarred_filename} with the compiled catalog for node #{node} and the necessary files" if debug

File.delete(catalog_file.path)
File.delete("#{node}.modulepath")
