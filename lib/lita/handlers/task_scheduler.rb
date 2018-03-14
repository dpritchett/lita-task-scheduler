module Lita
  module Handlers
    class TaskScheduler < Handler

      route /^schedule\s+"(.+)"\s+in\s+(.+)$/i, :schedule

      def schedule(payload)
        payload.matches.each do |task, timing|
          serialized = serialize_message(payload.message, new_body: task)
          resend(serialized)
        end
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
