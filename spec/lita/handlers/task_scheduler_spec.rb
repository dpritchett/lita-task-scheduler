require "spec_helper"

describe Lita::Handlers::TaskScheduler, lita_handler: true do
  let(:robot) { Lita::Robot.new(registry) }

  subject { described_class.new(robot) }

  describe ':schedule' do
    it { is_expected.to route('Lita schedule "show schedule" in 2 hours') }
    it { is_expected.to route("Lita show schedule") }

    it 'Displays the schedule' do
      send_message 'Lita schedule "show schedule" in 1 second'
      expect(replies.last.include?('Scheduled tasks')).to be_truthy
    end
  end

  describe ':parse_timing_2' do
    def time_drift(time, expected_seconds:)
      delta = (Time.now.utc - time).abs
      (expected_seconds - delta).abs
    end

    it 'parses seconds, minutes, hours, and days' do
      test_table = [
        ['3 seconds', 3],
        ['4 minutes', 4 * 60],
        ['2 hours', 2 * 60 * 60],
        ['5 days', 5 * 60 * 60 * 24]
      ]

      test_table.each do |input, expected|
        response = subject.parse_timing(input)
        drift = time_drift(response, expected_seconds: expected)
        expect(drift < 0.1).to be_truthy, "#{input}:\t #{expected}"
      end
    end
  end
end
