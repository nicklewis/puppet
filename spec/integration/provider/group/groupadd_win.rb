#!/usr/bin/env ruby

require 'spec_helper'

describe "Provider for windows groups", :if => Puppet.features.microsoft_windows? do

  require 'windowstest'
  include WindowsTest
  
  Puppet::Type.type(:user).provider(:useradd_win)

  before(:each) do
    @users_to_delete = []
    @groups_to_delete = []
  end
  
  after(:each) do
    delete_test_users
    delete_test_groups
  end   

  def group_provider(resource_configuration)
    provider = Puppet::Type.type(:group).provider(:groupadd_win).new
    provider.resource = resource_configuration
    return provider
  end

  it 'should create a group with configured members' do
    groupname = "randomgroup"
    delete_group_later groupname

    expected_members = ["test1", "test2"]
    create_test_users expected_members

    provider = group_provider :name => groupname, :members => ['test1', 'test2']
    provider.create

    group(groupname).members.sort.should be_eql(expected_members.sort)
  end

  it 'should set a groups members' do
    groupname = "randomgroup"
    expected_members = ["test1", "test2"]

    testgroup = create_test_groups(groupname)
    create_test_users(expected_members)

    provider = group_provider :name => groupname, :members => ['test1', 'test2']
    provider.members = ['test1', 'test2']

    group(groupname).members.sort.should be_eql(expected_members.sort)
  end
end
