require 'pry'

module Lita
  module Handlers
    class TaskScheduler < Handler

      route /^schedule\s+"(.+)"\s+in\s+(.+)$/i, :schedule
      route /^show schedule$/i, :show_schedule

      def show_schedule(payload)
        message = payload.matches.last
        payload.reply "Scheduled tasks:"
      end

      def schedule(payload)
        task,timing = payload.matches.last
        run_at = parse_timing(timing)
        puts run_at
        serialized = serialize_message(payload.message, new_body: task)
        resend(serialized)
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

        key = "delay_#{rand(100..10000)}"
        redis.set(key, serialized.to_json)
        reloaded = JSON.parse redis.get(key), symbolize_names: true

        resend(reloaded)
      end

      def resend(serialized)
        user = Lita::User.new(serialized.fetch(:user_name))
        room = Lita::Room.new(serialized.fetch(:room_name))
        source = Lita::Source.new(user: user, room: room)
        body = "#{robot.name} #{serialized.fetch(:body)}"

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
    end
  end
end
