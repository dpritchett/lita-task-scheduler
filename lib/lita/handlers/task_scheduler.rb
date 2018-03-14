module Lita
  module Handlers
    class TaskScheduler < Handler
      # insert handler code here
      #
      on :unhandled_message, :rebroadcast

      def rebroadcast(payload)
        serialized = serialize_message(payload)

        resend(serialized)
      end

      def resend(serialized)
        user = Lita::User.new(serialized.fetch(:user_name))
        room = Lita::Room.new(serialized.fetch(:room_name))
        source = Lita::Source.new(user: user, room: room)

        newmsg = Lita::Message.new(
          robot,
          "#{robot.name} double #{rand(1..100)}",
          source
        )

        robot.receive newmsg
      end

      def serialize_message(payload)
        msg = payload.fetch(:message)

        {
          user_name: msg.user.name,
          room_name: msg.source.room,
          body: msg.body
        }
      end

      Lita.register_handler(self)
    end
  end
end
