require 'json'

# START:preamble
module Lita
  class Scheduler
    REDIS_TASKS_KEY = name.to_s

    def initialize(redis:, logger:)
      @redis = redis
      @logger = logger
    end

    attr_reader :redis, :logger

    def get_all
      redis.hgetall(REDIS_TASKS_KEY)
    end
    # END:preamble

    # START:store_new
    def add(payload, timestamp)
      key_time = timestamp.to_i.to_s

      redis.watch(REDIS_TASKS_KEY)

      tasks = redis.hget(REDIS_TASKS_KEY, key_time) || []

      tasks = JSON.parse(tasks) unless tasks.empty?
      tasks << payload

      redis.hset(REDIS_TASKS_KEY, key_time, tasks.to_json)

      redis.unwatch
      tasks
    end
    # END:store_new

    def clear
      redis.del(REDIS_TASKS_KEY)
    end

    # START:find_tasks_due
    def find_tasks_due
      results = []
      timestamps = redis.hkeys(REDIS_TASKS_KEY)

      timestamps.each do |t|
        key_time = Time.at(t.to_i)
        next unless key_time <= Time.now

        tasks_raw = redis.hget(REDIS_TASKS_KEY, t)
        tasks = JSON.parse(tasks_raw)

        results += tasks
        redis.hdel(REDIS_TASKS_KEY, t)
      end

      results
    end
    # END:find_tasks_due
  end
end
