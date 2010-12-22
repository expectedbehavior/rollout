class Rollout
  def initialize(redis, memcache=nil)
    @redis  = redis
    @memcache = memcache
    @groups = {"all" => lambda { |user| true }}
  end

  def activate_group(feature, group)
    key = group_key(feature)
    @redis.sadd(key, group)
    update_cache_for_key(key)
  end

  def deactivate_group(feature, group)
    key = group_key(feature)
    @redis.srem(key, group)
    update_cache_for_key(key)
  end

  def deactivate_all(feature)
    @redis.del(group_key(feature))
    @redis.del(user_key(feature))
    @redis.del(percentage_key(feature))
    expire_cache_for_key(group_key(feature))
    expire_cache_for_key(user_key(feature))
    expire_cache_for_key(percentage_key(feature))
  end

  def activate_user(feature, user)
    key = user_key(feature)    
    @redis.sadd(key, user.id)
    update_cache_for_key(key)
  end

  def deactivate_user(feature, user)
    key = user_key(feature)
    @redis.srem(key, user.id)
    update_cache_for_key(key)
  end

  def define_group(group, &block)
    @groups[group.to_s] = block
  end

  def active?(feature, user)
    user_in_active_group?(feature, user) ||
      user_active?(feature, user) ||
        user_within_active_percentage?(feature, user)
  end

  def activate_percentage(feature, percentage)
    key = percentage_key(feature)
    @redis.set(key, percentage)
    update_cache_for_key(key, :string)
  end

  def deactivate_percentage(feature)
    key = percentage_key(feature)
    @redis.del(key)
    expire_cache_for_key(key)
  end

  private
    def key(name)
      "feature:#{name}"
    end

    def group_key(name)
      "#{key(name)}:groups"
    end

    def user_key(name)
      "#{key(name)}:users"
    end

    def percentage_key(name)
      "#{key(name)}:percentage"
    end

    def user_in_active_group?(feature, user)
      key = group_key(feature)
      if members = get_from_cache(key)
        if members == :nil
          members = []
        end
      else
        members = @redis.smembers(key) || []
      end
      members.any? { |group| @groups.key?(group.to_s) && @groups[group.to_s].call(user) }
    end

    def user_active?(feature, user)
      key = user_key(feature)
      if members = get_from_cache(key)
        if members == :nil
          return false
        end
        members.collect(&:to_s).include?(user.id.to_s)
      else
        @redis.sismember(key, user.id)
      end
    end

    def user_within_active_percentage?(feature, user)
      key = percentage_key(feature)
      if percentage = get_from_cache(key, :string) || @redis.get(key)
        if percentage == :nil
          return false
        end
        user.id % 100 < percentage.to_i
      end
    end

    def update_cache_for_key(key, type=:set)
      if @memcache
        value =
          if type == :set
            @redis.smembers(key)
          elsif type == :string
            @redis.get(key)
          end
        if value.nil?
          value = :nil
        end
        @memcache.set(key, value, 0)
        value
      end
    end

    def expire_cache_for_key(key)
      if @memcache
        @memcache.delete(key)
      end
    end

    def get_from_cache(key, type=:set)
      if @memcache
        begin
          @memcache.get_orig(key)
        rescue Memcached::NotFound
          update_cache_for_key(key, type)
        end
      end
    end
end
