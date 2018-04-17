require 'lita/scheduler'

module Lita
  module Handlers
    class TaskScheduler < Handler

      # START:routes
      route(/^schedule\s+"(.+)"\s+in\s+(.+)$/i, :schedule_command, command: true)
      route(/^show schedule$/i, :show_schedule, command: true)
      route(/^empty schedule$/i, :empty_schedule, command: true)
      # END:routes

      # START:handlers
      def show_schedule(payload)
        payload.reply schedule_report(scheduler.get_all)
      end

      def empty_schedule(payload)
        scheduler.clear
        show_schedule payload
      end

      # START:schedule_command
      def schedule_command(payload)
        task, timing = payload.matches.last
        run_at = parse_timing(timing)
        serialized = command_to_hash(payload.message, new_body: task)

        defer_task(serialized, run_at)
        show_schedule payload
      end
      # END:schedule_command

      def scheduler
        @_schedule ||= Scheduler.new(redis: redis, logger: Lita.logger)
      end

      def schedule_report(schedule)
        descriptions = []

        schedule.keys.each do |timestamp|
          play_time = Time.at(timestamp.to_i)
          tasks_json = schedule[timestamp]
          tasks = JSON.parse(tasks_json)

          tasks.each do |task|
            descriptions << "\n - \"#{task.fetch('body')}\" at #{play_time}"
          end
        end

        'Scheduled tasks: ' + (descriptions.empty? ? 'None.' : descriptions.join)
      end

      # START:defer_task
      def defer_task(serialized_task, run_at)
        scheduler.add(serialized_task, run_at)
      end
      # END:defer_task

      # START:parse_timing
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
      # END:parse_timing

      # START:resend_command
      def resend_command(command_hash)
        user = Lita::User.new(command_hash.fetch('user_name'))
        room = Lita::Room.new(command_hash.fetch('room_name'))
        source = Lita::Source.new(user: user, room: room)
        body = "#{robot.name} #{command_hash.fetch('body')}"

        newmsg = Lita::Message.new(
          robot,
          body,
          source
        )

        robot.receive newmsg
      end
      # END:resend_command

      # START:serialize_message
      def command_to_hash(command, new_body: nil)
        {
          user_name: command.user.name,
          room_name: command.source.room,
          body: new_body || command.body
        }
      end
      # END:serialize_message

      def find_tasks_due
        scheduler.find_tasks_due
      end

      # START:loop_ticks
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
        tasks.each { |t| resend_command t }
        Lita.logger.debug "Task loop done for #{Time.now}"
      end

      on(:loaded) { run_loop }
      # END:loop_ticks

      Lita.register_handler(self)
    end
  end
end
