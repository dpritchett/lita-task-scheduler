require 'pry'
require 'json'

module Lita
  module Handlers
    class TaskScheduler < Handler

      route(/^schedule\s+"(.+)"\s+in\s+(.+)$/i, :schedule_command, command: true)
      route(/^show schedule$/i, :show_schedule, command: true)
      route(/^empty schedule$/i, :empty_schedule, command: true)

      REDIS_TASKS_KEY = name.to_s

      def show_schedule(payload)
        schedule = redis.hgetall(REDIS_TASKS_KEY)

        payload.reply schedule_report(schedule)
      end

      def empty_schedule(payload)
        redis.del(REDIS_TASKS_KEY)
        show_schedule payload
      end

      def schedule_report(schedule)
        reply = 'Scheduled tasks: '
        descriptions = []

        schedule.keys.each do |timestamp|
          play_time = Time.at(timestamp.to_i)
          tasks_json = schedule[timestamp]
          tasks = JSON.parse(tasks_json)

          tasks.each do |task|
            descriptions << "\n - \"#{task.fetch('body')}\" at #{play_time}"
          end
        end

        reply + (descriptions.empty? ? 'None.' : descriptions.join)
      end

      def schedule_command(payload)
        task, timing = payload.matches.last
        run_at = parse_timing(timing)
        serialized = serialize_message(payload.message, new_body: task)

        defer_task(serialized, run_at)
        show_schedule(payload)
      end

      def defer_task(serialized_task, run_at)
        key_time = run_at.to_i.to_s

        redis.watch(REDIS_TASKS_KEY)

        tasks = redis.hget(REDIS_TASKS_KEY, key_time) || []

        tasks = JSON.parse(tasks) unless tasks.empty?
        tasks << serialized_task

        redis.hset(REDIS_TASKS_KEY, key_time, tasks.to_json)

        redis.unwatch

        tasks
      end

      def execute_tasks(serialized_tasks)
        serialized_tasks.each do |serialized_task|
          Lita.logger.debug "Resending task #{serialized_task}"
          resend serialized_task
        end
      end

      def run_loop
        Thread.new do
          loop do
            tick
            sleep 1
          end
        end
      end

      def tick
        tasks = find_tasks_due
        tasks.each { |t| resend t }
        Lita.logger.debug "Task loop done for #{Time.now}"
      end

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

      def parse_timing(timing)
        count, unit = timing.split
        count = count.to_i
        unit = unit.downcase.strip.gsub(/s$/, '')

        seconds = case unit
                  when 'second'
                    count
                  when 'minute'
                    count * 60
                  when 'hour'
                    count * 60 * 60
                  when 'day'
                    count * 60 * 60 * 24
                  else
                    raise ArgumentError, "I don't recognize #{unit}"
                  end

        Time.now.utc + seconds
      end

      def rebroadcast(payload)
        serialized = serialize_message(payload.message)

        key = "delay_#{rand(100..10_000)}"
        redis.set(key, serialized.to_json)
        reloaded = JSON.parse redis.get(key), symbolize_names: true

        resend(reloaded)
      end

      def resend(serialized)
        user = Lita::User.new(serialized.fetch('user_name'))
        room = Lita::Room.new(serialized.fetch('room_name'))
        source = Lita::Source.new(user: user, room: room)
        body = "#{robot.name} #{serialized.fetch('body')}"

        newmsg = Lita::Message.new(
          robot,
          body,
          source
        )

        robot.receive newmsg
      end

      def serialize_message(message, new_body: nil)
        {
          user_name: message.user.name,
          room_name: message.source.room,
          body: new_body || message.body
        }
      end

      Lita.register_handler(self)

      on :loaded do
        run_loop
      end
    end
  end
end
