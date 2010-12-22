require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Rollout" do
  before do
    @redis = Redis.new
    @memcache = Memcached::Rails.new($memcache_config[:servers])
    @rollout = Rollout.new(@redis, @memcache)
  end

  describe "when a group is activated" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :fivesonly)      
    end

    it "the feature is active for users for which the block evaluates to true" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "is not active for users for which the block evaluates to false" do
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end

    it "is not active if a group is found in Redis but not defined in Rollout" do
      @rollout.activate_group(:chat, :fake)
      @rollout.should_not be_active(:chat, stub(:id => 1))
    end
    
    it "should update the cache" do
      @rollout.should_receive(:update_cache_for_key).with(@rollout.send(:group_key, :chat))
      @rollout.activate_group(:chat, :fake)
    end
  end
  
  describe "the default all group" do
    before do
      @rollout.activate_group(:chat, :all)
    end

    it "evaluates to true no matter what" do
      @rollout.should be_active(:chat, stub(:id => 0))
    end
  end

  describe "deactivating a group" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.deactivate_group(:chat, :all)
    end

    it "deactivates the rules for that group" do
      @rollout.should_not be_active(:chat, stub(:id => 10))
    end

    it "leaves the other groups active" do
      @rollout.should be_active(:chat, stub(:id => 5))
    end

    it "should update the cache" do
      @rollout.should_receive(:update_cache_for_key).with(@rollout.send(:group_key, :chat))
      @rollout.deactivate_group(:chat, :all)
    end
  end

  describe "deactivating a feature completely" do
    before do
      @rollout.define_group(:fivesonly) { |user| user.id == 5 }
      @rollout.activate_group(:chat, :all)
      @rollout.activate_group(:chat, :fivesonly)
      @rollout.activate_user(:chat, stub(:id => 51))
      @rollout.activate_percentage(:chat, 100)
      @rollout.deactivate_all(:chat)
    end

    it "removes all of the groups" do
      @rollout.should_not be_active(:chat, stub(:id => 0))
    end

    it "removes all of the users" do
      @rollout.should_not be_active(:chat, stub(:id => 51))
    end

    it "removes the percentage" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end

    it "should delete the keys from the cache" do
      @rollout.should_receive(:expire_cache_for_key).with(@rollout.send(:group_key, :chat))
      @rollout.should_receive(:expire_cache_for_key).with(@rollout.send(:user_key, :chat))
      @rollout.should_receive(:expire_cache_for_key).with(@rollout.send(:percentage_key, :chat))
      @rollout.deactivate_all(:chat)
    end
  end

  describe "activating a specific user" do
    before do
      @rollout.activate_user(:chat, stub(:id => 42))
    end

    it "is active for that user" do
      @rollout.should be_active(:chat, stub(:id => 42))
    end

    it "remains inactive for other users" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end

    it "should update the cache" do
      @rollout.should_receive(:update_cache_for_key).with(@rollout.send(:user_key, :chat))
      @rollout.activate_user(:chat, stub(:id => 24))
    end
  end

  describe "deactivating a specific user" do
    before do
      @rollout.activate_user(:chat, stub(:id => 42))
      @rollout.activate_user(:chat, stub(:id => 24))
      @rollout.deactivate_user(:chat, stub(:id => 42))
    end

    it "that user should no longer be active" do
      @rollout.should_not be_active(:chat, stub(:id => 42))
    end

    it "remains active for other active users" do
      @rollout.should be_active(:chat, stub(:id => 24))
    end

    it "should update the cache" do
      @rollout.should_receive(:update_cache_for_key).with(@rollout.send(:user_key, :chat))
      @rollout.deactivate_user(:chat, stub(:id => 24))
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      (1..120).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should == 39
    end

    it "should update the cache" do
      @rollout.should_receive(:update_cache_for_key).with(@rollout.send(:percentage_key, :chat), :string)
      @rollout.activate_percentage(:chat, 20)
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 20)
    end

    it "activates the feature for that percentage of the users" do
      (1..200).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should == 40
    end
  end

  describe "activating a feature for a percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 5)
    end

    it "activates the feature for that percentage of the users" do
      (1..100).select { |id| @rollout.active?(:chat, stub(:id => id)) }.length.should == 5
    end
  end


  describe "deactivating the percentage of users" do
    before do
      @rollout.activate_percentage(:chat, 100)
      @rollout.deactivate_percentage(:chat)
    end

    it "becomes inactivate for all users" do
      @rollout.should_not be_active(:chat, stub(:id => 24))
    end
    
    it "should delete the key from the cache" do
      @rollout.should_receive(:expire_cache_for_key).with(@rollout.send(:percentage_key, :chat))
      @rollout.deactivate_percentage(:chat)
    end
  end
  
  describe 'updating a cache' do
    before(:each) do
      @redis = mock(:redis)
      @rollout = Rollout.new(@redis, @memcache)
    end
    context 'for groups' do
      before(:each) do
        @key = @rollout.send(:group_key, :test)
        @set = ['test']
      end

      it "should get the members of the set from redis" do
        @redis.should_receive(:smembers).with(@key).and_return(@set)
        @rollout.send(:update_cache_for_key, @key)
      end
      
      it "should write the members to the cache" do
        @redis.stub!(:smembers).and_return(@set)
        @memcache.should_receive(:set).with(@key, @set, anything)
        @rollout.send(:update_cache_for_key, @key)
      end
    end

    context 'for users' do
      before(:each) do
        @key = @rollout.send(:user_key, :test)
        @set = ['test']
      end

      it "should get the members of the set from redis" do
        @redis.should_receive(:smembers).with(@key).and_return(@set)
        @rollout.send(:update_cache_for_key, @key)
      end

      it "should write the members to the cache" do
        @redis.stub!(:smembers).and_return(@set)
        @memcache.should_receive(:set).with(@key, @set, anything)
        @rollout.send(:update_cache_for_key, @key)
      end
    end

    context 'for a percentage' do
      before(:each) do
        @key = @rollout.send(:percentage_key, :test)
        @percentage = 50
      end

      it "should get the percentage from redis" do
        @redis.should_receive(:get).with(@key).and_return(0)
        @rollout.send(:update_cache_for_key, @key, :string)
      end

      it "should write the members to the cache" do
        @redis.stub!(:get).and_return(@percentage)
        @memcache.should_receive(:set).with(@key, @percentage, anything)
        @rollout.send(:update_cache_for_key, @key, :string)
      end
    end
  end
  
  describe 'get from cache' do
    before(:each) do
      @key = @rollout.send(:group_key, :test)
    end

    it "should attempt to get the value from memcache" do
      @memcache.should_receive(:get_orig).with(@key)
      @rollout.send(:get_from_cache, @key)
    end
    
    it "should update the cache on a miss" do
      @memcache.stub!(:get_orig).with(@key).and_raise(Memcached::NotFound)
      @rollout.should_receive(:update_cache_for_key).with(@key, :set)
      @rollout.send(:get_from_cache, @key)
    end    
  end

  describe 'expire the cache' do
    before(:each) do
      @key = @rollout.send(:group_key, :test)
    end

    it "should delete the key from memcache" do
      @memcache.should_receive(:delete).with(@key)
      @rollout.send(:expire_cache_for_key, @key)
    end
  end
  
  describe 'user in active groups' do
    before(:each) do
      @redis = mock(:redis)
      @rollout = Rollout.new(@redis, @memcache)
      @key = @rollout.send(:group_key, :chat)
      @redis.stub!(:sadd).with(@key, :fivesonly)
      @redis.stub!(:smembers).with(@key).and_return(['fivesonly'])
      @rollout.activate_group(:chat, :fivesonly)
    end
    
    it "should use the cached valued" do
      @memcache.should_receive(:get_orig).with(@key).and_return(['fivesonly'])
      @redis.should_not_receive(:smembers).with(@key)
      @rollout.send(:user_in_active_group?, :chat, stub(:id => 5))
    end
    
    it "should fallback to the redis value" do
      @memcache.should_receive(:get_orig).with(@key).and_return(nil)
      @redis.should_receive(:smembers).with(@key).and_return(['fivesonly'])
      @rollout.send(:user_in_active_group?, :chat, stub(:id => 5))
    end
  end

  describe 'user active' do
    before(:each) do
      @redis = mock(:redis)
      @rollout = Rollout.new(@redis, @memcache)
      @key = @rollout.send(:user_key, :chat)
      @redis.stub!(:sadd).with(@key, 5)
      @redis.stub!(:sismember).with(@key, 5).and_return(true)
      @redis.stub!(:smembers).with(@key).and_return(['5'])
      @rollout.activate_user(:chat, stub(:id => 5))
    end
    
    it "should use the cached valued" do
      @memcache.should_receive(:get_orig).with(@key).and_return(['5'])
      @redis.should_not_receive(:smembers).with(@key)
      @rollout.send(:user_active?, :chat, stub(:id => 5))
    end
    
    it "should fallback to the redis value" do
      @memcache.should_receive(:get_orig).with(@key).and_raise(Memcached::NotFound)
      @redis.should_receive(:smembers).with(@key).and_return(['5'])
      @rollout.send(:user_active?, :chat, stub(:id => 5))
    end
  end
  
  describe 'user within active percentage' do
    before(:each) do
      @redis = mock(:redis)
      @rollout = Rollout.new(@redis, @memcache)
      @key = @rollout.send(:percentage_key, :chat)
      @redis.stub!(:set).with(@key, 50)
      @redis.stub!(:get).with(@key).and_return(50)
      @rollout.activate_percentage(:chat, 50)
    end
    
    it "should use the cached valued" do
      @memcache.should_receive(:get_orig).with(@key).and_return('50')
      @redis.should_not_receive(:get).with(@key)
      @rollout.send(:user_within_active_percentage?, :chat, stub(:id => 5))
    end
    
    it "should fallback to the redis value" do
      @memcache.should_receive(:get_orig).with(@key).and_raise(Memcached::NotFound)
      @redis.should_receive(:get).with(@key).and_return('50')
      @rollout.send(:user_within_active_percentage?, :chat, stub(:id => 5))
    end
  end

end
