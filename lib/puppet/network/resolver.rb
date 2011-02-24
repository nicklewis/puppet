require 'resolv'
module Puppet::Network; end

module Puppet::Network::Resolver
  # Iterate through the list of servers that service this hostname
  # and yield each server/port since SRV records have ports in them
  # It will override whatever masterport setting is already set.
  def self.each_srv_record(srv)
    Puppet.debug "Searching for SRV records for #{srv}"

    resolver = Resolv::DNS.new
    records = resolver.getresources(srv, Resolv::DNS::Resource::IN::SRV)

    Puppet.debug "Found #{records.size} SRV records."

    each_priority(records) do |priority, records|
      while next_rr = records.delete(find_weighted_server(records))
        Puppet.debug "Yielding next server of #{next_rr.target.to_s}:#{next_rr.port}"
        yield next_rr.target.to_s, next_rr.port
      end
    end
  end

  private

  def self.each_priority(records)
    pri_hash = records.inject({}) do |groups, element|
      groups[element.priority] ||= []
      groups[element.priority] << element
      groups
    end

    pri_hash.keys.sort.each { |key| yield key, pri_hash[key] }
  end

  def self.find_weighted_server(records)
    return nil if records.nil? || records.empty?
    return records.first if records.size == 1

    # Calculate the sum of all weights in the list of resource records,
    # This is used to then select hosts until the weight exceeds what
    # random number we selected.  For example, if we have weights of 1 8 and 3:
    #
    # |-|---|--------|
    #        ^
    # We generate a random number 5, and iterate through the records, adding
    # the current record's weight to the accumulator until the weight of the
    # current record plus previous records is greater than the random number.

    total_weight = records.inject(0) { |sum,record|
      sum + weight(record)
    }
    current_weight = 0
    chosen_weight  = 1 + Kernel.rand(total_weight)

    records.each do |record|
      current_weight += weight(record)
      return record if current_weight >= chosen_weight
    end
  end

  def self.weight(record)
    record.weight == 0 ? 1 : record.weight * 10
  end
end
