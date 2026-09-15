# frozen_string_literal: true

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

RSpec.describe MaskJobRuntimeConflict do
  # These examples run against the real Redis the host test suite already
  # needs: real Redlock locks, and Sidekiq process/work entries written the
  # way Sidekiq's heartbeat writes them, then read back through the real
  # Sidekiq::Workers. Only the Sentry constant is faked, because the sentry
  # gems are absent from the host test bundle (they arrive via Gemfile.theme
  # at deploy time), so there is no real Sentry to point at.
  let(:sentry) { double('Sentry', capture_message: nil, capture_exception: nil) }

  let(:attachment) { FactoryBot.create(:body_text) }
  let(:job) { FoiAttachmentMaskJob.new(attachment) }
  let(:lock_key) { job.runtime_lock_key }
  let(:lock_manager) { ActiveJob::Uniqueness.lock_manager }

  # Sidekiq identities are "hostname:pid:nonce"; the nonce keeps this clear of
  # any real Sidekiq process sharing the Redis.
  let(:process_id) { "spec-host:#{Process.pid}:mask_job_runtime_conflict_spec" }
  let(:work_key) { "#{process_id}:work" }

  before do
    stub_const('Sentry', sentry)
    allow(Rails.logger).to receive(:warn).and_call_original
  end

  after do
    lock_manager.delete_lock(lock_key)
    Sidekiq.redis do |conn|
      conn.srem('processes', [process_id])
      conn.del(work_key)
    end
  end

  def plant_lock(ttl_ms)
    expect(lock_manager.lock(lock_key, ttl_ms)).to be_truthy
  end

  # Mirrors Sidekiq::Launcher#❤ (6.5.12): the process joins the `processes`
  # set and its in-flight jobs sit in a `<identity>:work` hash, one field per
  # thread, holding the queue, the raw job payload and the start time.
  def plant_in_flight(payload)
    work = {
      'queue' => 'default',
      'payload' => Sidekiq.dump_json(payload),
      'run_at' => Time.now.to_i
    }

    Sidekiq.redis do |conn|
      conn.sadd('processes', [process_id])
      conn.hset(work_key, 'tid-1', Sidekiq.dump_json(work))
      conn.expire(work_key, 60)
    end
  end

  def mask_job_payload(for_job)
    {
      'class' => 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper',
      'wrapped' => 'FoiAttachmentMaskJob',
      'queue' => 'default',
      'args' => [for_job.serialize]
    }
  end

  def call
    described_class.call(job)
  end

  context 'when the lock is younger than the heartbeat grace period' do
    before { plant_lock(30.minutes.in_milliseconds) }

    it 'leaves the lock alone' do
      call
      expect(lock_manager.locked?(lock_key)).to eq(true)
    end

    it 'does not report to Sentry' do
      call
      expect(sentry).not_to have_received(:capture_message)
    end
  end

  context 'when an in-flight job holds the lock' do
    # A one minute TTL against a 30 minute runtime_lock_ttl reads as a lock
    # that is 29 minutes old, well past the grace period.
    before do
      plant_lock(1.minute.in_milliseconds)
      plant_in_flight(mask_job_payload(job))
    end

    it 'leaves the lock alone' do
      call
      expect(lock_manager.locked?(lock_key)).to eq(true)
    end

    it 'does not report to Sentry' do
      call
      expect(sentry).not_to have_received(:capture_message)
    end
  end

  context 'when the lock is old and nothing is running behind it' do
    before { plant_lock(1.minute.in_milliseconds) }

    it 'deletes the lock' do
      call
      expect(lock_manager.locked?(lock_key)).to eq(false)
    end

    it 'reports the stranded lock to Sentry' do
      call
      expect(sentry).to have_received(:capture_message).with(
        a_string_matching(/stranded/),
        hash_including(
          level: :error,
          fingerprint: ['mask_job_stranded_lock', attachment.id.to_s],
          extra: hash_including(
            attachment_id: attachment.id,
            lock_key: lock_key,
            remaining_ttl_ms: a_value_between(1, 1.minute.in_milliseconds),
            lock_deleted: true
          )
        )
      )
    end

    it 'warns in the log' do
      call
      expect(Rails.logger).to have_received(:warn).with(
        a_string_including("FoiAttachment #{attachment.id}", lock_key)
      )
    end

    it 'ignores an in-flight mask job for a different attachment' do
      other_job = FoiAttachmentMaskJob.new(FactoryBot.create(:body_text))
      plant_in_flight(mask_job_payload(other_job))

      call

      expect(lock_manager.locked?(lock_key)).to eq(false)
      expect(sentry).to have_received(:capture_message)
    end
  end

  context 'when the lock has already gone' do
    it 'does nothing' do
      call
      expect(sentry).not_to have_received(:capture_message)
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including(lock_key))
    end
  end

  context 'when the check itself fails' do
    # A job whose argument is not a record cannot be matched against
    # Sidekiq::Workers (no GlobalID), which is the cheapest real failure
    # inside the callback that needs no stubbing of Redis or Sidekiq.
    let(:job) { FoiAttachmentMaskJob.new('not an attachment') }

    before { plant_lock(1.minute.in_milliseconds) }

    it 'does not raise' do
      expect { call }.not_to raise_error
    end

    it 'leaves the lock alone and reports the exception' do
      call
      expect(lock_manager.locked?(lock_key)).to eq(true)
      expect(sentry).to have_received(:capture_exception).with(an_instance_of(NoMethodError))
      expect(Rails.logger).to have_received(:warn).with(a_string_including(lock_key))
    end
  end
end
