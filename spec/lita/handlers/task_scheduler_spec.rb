require 'spec_helper'

describe Lita::Handlers::TaskScheduler, lita_handler: true do
  let(:robot) { Lita::Robot.new(registry) }

  subject { described_class.new(robot) }

  describe 'routing' do
    it { is_expected.to route('Lita schedule "show schedule" in 2 hours') }
    it { is_expected.to route('Lita show schedule') }
  end

  describe 'functionality' do

    describe ':schedule_report' do
      context 'tasks are scheduled'
      before do
        send_message 'Lita schedule "show schedule" in 1 seconds'
        send_message 'Lita schedule "show schedule" in 6 seconds'
      end

      it 'should list scheduled tasks on demand' do
        message = double 'message'
        expect(message).to receive(:reply)
        subject.show_schedule(message)
        send_message 'Lita show schedule'
      end
    end

    describe ':defer_task' do
      it 'defers any single task' do
        message = { canary_message: Time.now }
        run_at = Time.now + 5
        result = subject.defer_task(message, run_at)
        expect(result).to include(message)
      end

      it 'stores multiple same-second tasks in an array' do
        message = { 'canary_message' => Time.now.to_i }
        run_at = Time.now + 5

        5.times do
          subject.defer_task(message, run_at)
        end

        result = subject.defer_task(message, run_at)

        expect(result).to eq([message] * 6)
      end
    end

    describe ':find_tasks_due' do
      context 'two tasks are scheduled for five seconds ago' do
        before { 2.times { subject.defer_task('past_task', Time.now - 5) } }

        it 'returns all past due tasks' do
          result = subject.find_tasks_due
          expected = %w[past_task past_task]
          expect(result).to eq(expected)
        end
      end

      context 'one task scheduled in the future' do
        before { subject.defer_task('future_task', Time.now + 100) }

        it 'does not return that new task' do
          result = subject.find_tasks_due
          expect(result).to_not include('future_task')
        end
      end
    end
  end

  describe 'execute_tasks' do
    it 'resends each task' do
      tasks = [{}, {}]

      expect(subject).to receive(:resend).exactly(2).times
      subject.execute_tasks(tasks)
    end
  end

  describe 'tick' do
    before { subject.stub(:find_tasks_due).and_return ['a_task'] }

    it 'should find tasks due and resend them' do
      expect(subject).to receive(:find_tasks_due)
      expect(subject).to receive(:resend).with('a_task')

      subject.tick
    end
  end

  describe ':parse_timing' do
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
