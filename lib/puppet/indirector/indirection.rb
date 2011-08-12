require 'puppet/util/docs'
require 'puppet/indirector/envelope'
require 'puppet/indirector/request'

# The class that connects functional classes with their different collection
# back-ends.  Each indirection has a set of associated terminus classes,
# each of which is a subclass of Puppet::Indirector::Terminus.
class Puppet::Indirector::Indirection
  include Puppet::Util::Docs

  @@indirections = {}

  # Find an indirection by name.  This is provided so that Terminus classes
  # can specifically hook up with the indirections they are associated with.
  def self.instance(name)
    @@indirections[name]
  end

  # Return a list of all known indirections.  Used to generate the
  # reference.
  def self.instances
    @@indirections.keys
  end

  # Find an indirected model by name.  This is provided so that Terminus classes
  # can specifically hook up with the indirections they are associated with.
  def self.model(name)
    match.model if match = instance(name)
  end

  attr_accessor :name, :model

  # This is only used for testing.
  def delete
    @@indirections.delete(self.name)
  end

  # Generate the full doc string.
  def doc
    text = ""

    text += scrub(@doc) + "\n\n" if @doc

    text
  end

  attr_reader :terminuses

  def initialize(model, name, options = {})
    @model = model
    @name = name
    @terminuses = Hash.new []

    raise(ArgumentError, "Indirection #{@name} is already defined") if @@indirections[@name]
    @@indirections[@name] = self

    if mod = options.delete(:extend)
      extend(mod)
    end

    if terminus_class = options.delete(:terminus_class)
      self.terminus_class = terminus_class
    end

    @terminus_setting = options.delete(:terminus_setting)
  end

  def primary_terminuses_for(method)
    terminuses = @terminuses[method] || default_terminuses_for(method)

    raise "No '#{method}' terminus specified for indirection #{name}" if terminuses.empty?

    terminuses
  end

  def default_terminuses_for(method)
    # Yay!
    case method
    when :head, :find, :destroy
      [default_cache, default_terminus]
    when :save
      [default_terminus, default_cache]
    when :search
      [default_terminus]
    end.compact
  end

  # This is for backward compatibility with terminus_setting
  def default_terminus
    return @default_terminus if @default_terminus
    self.terminus_class = Puppet[@terminus_setting] if @terminus_setting
    @default_terminus
  end

  def default_cache
    @default_cache
  end

  # These are really for backward compatibility, so we don't have to immediately
  # start specifying *every* route explicitly
  def terminus_class=(terminus_class)
    if terminus_class
      validate_terminus_class(terminus_class)
      @default_terminus = make_terminus(terminus_class)
    else
      @default_terminus = nil
    end
  end

  def cache_class=(terminus_class)
    if terminus_class
      validate_terminus_class(terminus_class)
      @default_cache = make_terminus(terminus_class)
    else
      @default_cache = nil
    end
  end

  def reset_all_terminuses
    reset_terminuses
    reset_default_terminuses
  end

  def reset_terminuses
    @terminuses = {}
  end

  def reset_default_terminuses
    @default_terminus = nil
    @default_cache    = nil
  end

  # This is used by terminus_class= and cache=.
  def validate_terminus_class(terminus_class)
    raise ArgumentError, "Invalid terminus name #{terminus_class.inspect}" unless terminus_class and terminus_class.to_s != ""
    unless Puppet::Indirector::Terminus.terminus_class(self.name, terminus_class)
      raise ArgumentError, "Could not find terminus #{terminus_class} for indirection #{self.name}"
    end
  end

  #def method_missing(method, *args)
  #  method = method.to_s
  #  if type = [/^find_from_/, /^save_to_/, /^search_thru_/, /^destroy_from_/, /^head_from_/].find {|r| method =~ r}
  #    name = type.chomp('_')
  #    terminuses = (method - name).split('_').map(&:to_sym)
  #    send(method_name, *args)
  #  else
  #    super
  #  end
  #end

  def find_from(terminuses, key, *args)
    request = Puppet::Indirector::Request.new(name, :find, key, *args)
    fail_unless_authorized(request, terminuses)

    Puppet.debug "Finding #{model.name} from #{terminuses.map(&:name).map(&:to_s).inspect}"

    result = nil
    error = nil
    terminuses.each do |terminus|
      begin
        if result = terminus.find(request)
          return result
        end
        error = nil
      rescue => e
        error = e
      end
    end

    # If we get here, we found nothing. Maybe something bad happened.
    raise error if error

    nil
  end

  # Search for an instance in the appropriate terminus, saving the results.
  def find(key, *args)
    find_from(primary_terminuses_for(:find), key, *args)
  end

  def head_from(terminuses, key, *args)
    request = Puppet::Indirector::Request.new(name, :head, key, *args)
    fail_unless_authorized(request, terminuses)

    terminuses.any? { |terminus| terminus.head(request) }
  end

  # This attempts a head request against every terminus, and returns true if
  # any one of them returns true.
  def head(key, *args)
    head_from(primary_terminuses_for(:find), key, *args)
  end

  def destroy_from(terminuses, key, *args)
    request = Puppet::Indirector::Request.new(name, :destroy, key, *args)
    fail_unless_authorized(request, terminuses)

    terminuses.each { |t| t.destroy(request) rescue nil }
    nil
  end

  # Remove something via the terminus.
  # Destroy presently destroys from all the save terminuses (essentially these
  # are defined as terminuses over the data of which we have authority).
  def destroy(key, *args)
    destroy_from(primary_terminuses_for(:save), key, *args)
  end

  def search_thru(terminuses, key, *args)
    request = Puppet::Indirector::Request.new(name, :search, key, *args)
    fail_unless_authorized(request, terminuses)

    terminuses.map { |terminus| terminus.search(request) }.inject(&:|)
  end

  # Search for more than one instance.  Should always return an array.
  # Search is presently defined to return the union of the results of searching
  # each find terminus. May or may not be the correct behavior.
  def search(key, *args)
    search_thru(primary_terminuses_for(:find), key, *args)
  end

  def save_to(terminuses, instance, key = nil)
    request = Puppet::Indirector::Request.new(name, :save, key, instance)
    fail_unless_authorized(request, terminuses)

    Puppet.debug "Saving #{model.name} to #{terminuses.map(&:name).map(&:to_s).inspect}"

    results = terminuses.map {|terminus| terminus.save(request) }

    assert_that "all save terminuses should return the instance provided" do
      results.all? {|res| res == instance}
    end

    results.first
  end

  # Save the instance in the appropriate terminus.  This method is
  # normally an instance method on the indirected class.
  def save(instance, key = nil)
    save_to(primary_terminuses_for(:save), instance, key)
  end

  # Create a new terminus instance.
  def make_terminus(terminus_class)
    # Load our terminus class.
    unless klass = Puppet::Indirector::Terminus.terminus_class(self.name, terminus_class)
      raise ArgumentError, "Could not find terminus #{terminus_class} for indirection #{self.name}"
    end
    klass.new
  end

  private

  # Check authorization if there's a hook available; fail if there is one
  # and it returns false.
  def fail_unless_authorized(request, terminuses)
    # At this point, we're assuming authorization makes no sense without
    # client information.
    return unless request.node

    # This is only to authorize via a terminus-specific authorization hook.
    authorizing_terminuses = terminuses.select {|t| t.respond_to?(:authorized?)}
    return unless authorizing_terminuses.any?

    unless authorizing_terminuses.all? {|t| t.authorized?(request)}
      msg = "Not authorized to call #{request.method} on #{request}"
      msg += " with #{request.options.inspect}" unless request.options.empty?
      raise ArgumentError, msg
    end
  end
end
