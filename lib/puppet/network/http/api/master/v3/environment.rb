require 'json'
require 'puppet/parser/environment_compiler'

class Puppet::Network::HTTP::API::Master::V3::Environment
  def call(request, response)
    env_name = request.routing_path.split('/').last
    env = Puppet.lookup(:environments).get(env_name)

    catalog = Puppet::Parser::EnvironmentCompiler.compile(env).to_resource

    env_graph = {:environment => env.name, :applications => {}}
    applications = catalog.resources.select do |res|
      type = res.resource_type
      type.is_a?(Puppet::Resource::Type) && type.application?
    end
    applications.each do |app|
      app_components = {}
      catalog.direct_dependents_of(app).each do |comp|
        type = comp.resource_type
        params = comp.to_hash
        consumes = params.select { |p| Array(type.consumes).include?(p) }.values
        consumes = consumes.flatten.map(&:ref)
        params = params.select { |p| ! type.consumes.include?(p) }
        produces = catalog.direct_dependents_of(comp)

        node = app['nodes'].find { |node, components| components.map(&:ref).include?(comp.ref) }.first.title
        app_components[comp.ref] = {:produces => produces.map(&:ref), :consumes => consumes, :node => node}
      end
      env_graph[:applications][app.ref] = app_components
    end
    response.respond_with(200, "application/json", JSON.dump(env_graph))
  end
end

