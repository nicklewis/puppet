require 'json'
require 'puppet/parser/environment_compiler'

class Puppet::Network::HTTP::API::Master::V3::Environment
  def call(request, response)
    env_name = request.routing_path.split('/').last
    env = Puppet.lookup(:environments).get(env_name)

    catalog = Puppet::Parser::EnvironmentCompiler.compile(env).to_resource

    applications = catalog.resources.select do |res|
      type = res.resource_type
      type.is_a?(Puppet::Resource::Type) && type.application?
    end
    app_instances = applications.map do |app|
      app_components = catalog.direct_dependents_of(app).map do |comp|
        type = comp.resource_type
        params = comp.to_hash
        consumes = params.select { |p| Array(type.consumes).include?(p) }.values
        consumes = consumes.flatten.map { |c| {:type => c.type, :title => c.title} }
        produces = catalog.direct_dependents_of(comp).map { |p| {:type => p.type, :title => p.title} }

        mapped_nodes = app['nodes'].select { |node, components| components.map(&:ref).include?(comp.ref) }.map { |node, components| node.title }

        if mapped_nodes.length > 1
          raise Puppet::ParseError, "Component #{comp} is mapped to multiple nodes: #{mapped_nodes.join(', ')}"
        elsif mapped_nodes.empty?
          raise Puppet::ParseError, "Component #{comp} is not mapped to any node"
        else
          mapped_node = mapped_nodes.first
        end

        {:type => comp.type, :title => comp.title, :produces => produces, :consumes => consumes, :node => mapped_node}
      end
      {:type => app.type, :title => app.title, :components => app_components}
    end
    env_graph = {:environment => env.name, :applications => app_instances}
    response.respond_with(200, "application/json", JSON.dump(env_graph))
  end
end

