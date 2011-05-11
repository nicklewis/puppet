Puppet::Face.define(:script, '0.0.1') do
  action(:execute) do
    default
    when_invoked do |manifest, *options|
      # Get rid of regular "options"
      options.pop

      raise "Could not find file #{manifest}" unless File.exist?(manifest)
      Puppet[:manifest] = manifest

      parameters = {}

      options.each do |opt|
        raise "Option #{opt} is not of form param=value" unless opt =~ /^((?:\w|::)+)=(.+)$/
        name, value = $1, $2
        raise "Parameters #{name} declared twice, first with #{parameters[name]}, now with #{value}" if parameters.has_key?(name)
        parameters[name] = value
      end

      node = Puppet::Node.new(Puppet[:certname], :parameters => parameters)

      unless facts = Puppet::Node::Facts.indirection.find(Puppet[:certname])
        raise "Could not find facts for #{Puppet[:certname]}"
      end

      node.merge(facts.values)

      starttime = Time.now
      catalog = Puppet::Resource::Catalog.indirection.find(node.name, :use_node => node)

      # Translate it to a RAL catalog
      catalog = catalog.to_ral

      catalog.finalize

      catalog.retrieval_duration = Time.now - starttime

      require 'puppet/configurer'
      configurer = Puppet::Configurer.new
      configurer.run(:skip_plugin_download => true, :catalog => catalog)
    end
  end
end
