require 'lita/scheduler'

module Lita
  module Handlers
    class TaskScheduler < Handler

      route(/^schedule\s+"(.+)"\s+in\s+(.+)$/i, :schedule_command, command: true)
      route(/^show schedule$/i, :show_schedule, command: true)
      route(/^empty schedule$/i, :empty_schedule, command: true)

      def scheduler
        @_schedule ||= Scheduler.new(redis: redis, logger: Lita.logger)
      end

      def show_schedule(payload)
        payload.reply schedule_report(scheduler.get)
      end

      def empty_schedule(payload)
        scheduler.clear
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
        scheduler.add(serialized_task, run_at)
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
        scheduler.find_tasks_due
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
